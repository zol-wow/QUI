-- tests/taint/analyzer.lua
-- Static taint-flow analyzer. Accepts Lua source + filename, returns a list of
-- Finding records.
--
-- ROUND-8 (2026-07 external 12.1 review follow-up), all fixture-covered in
-- analyzer_test.lua:
--   * unproven truth-tests of tainted refs in and/or chains EMIT (the
--     round-6b "existence tests are engine-legal" exemption and the or-
--     defaulting carve-out are gone — `if updateInfo and updateInfo.f` and
--     `tainted or dflt` throw in-game on a secret)
--   * terminator-aware guard untaint: `if guard(x) then return end` proves x
--     for the code after the if; guard-clause falsity protects subsequent
--     clauses and the fall-through union contribution
--   * restriction-gate dominance in the TAINT walk (bail idiom + negative
--     branches), scoped to PAYLOAD-derived (aura-class) taint only — a falsy
--     aura gate no longer blesses cooldown-class / unconditional secrets
--     (prove()'s "*" wildcard is reinterpreted by provenCovers)
--   * guard aliases resolve through the file-scope alias maps with the same
--     poisoning discipline as gates (isGuardName)
--
-- ROUND-10 closes the recurring syntax-adjacency gaps with fixture matrices:
-- complete expression-node traversal, direct source truth-tests, positional
-- select/pcall flow, exact dotted/keyed guard proofs, constructor provenance,
-- numeric-for and assignment-key sinks, event-specific dispatch positions,
-- and path-aware RegisterEvent/SetScript linkage (aliases, stable dotted
-- receivers, simple factories, replacements, and mutually exclusive arms).
--
-- Remaining deliberate boundary: aspect-returning widget getters still need
-- receiver provenance (Blizzard-owned/secretized surface vs QUI-created
-- chrome) before broad aspect_paths can be enabled; see tests/.taintrc.lua.
-- Handler factories with arbitrary interprocedural control/data flow remain
-- outside this intrafile analyzer; direct returned closures are modeled.
--
-- ROUND-13/13b (2026-07-18, Drew's "secret-to-state collapse" audit): new
-- <secret-collapse> rule — guard-secret-dominated branches flag literal
-- returns and literal member/index state writes; the only suppression is
-- `-- @secret-policy: <name>` (a named ACTION POLICY), `@secret-safe` does
-- not apply to this sink. Unknown METHOD consumers now default-reject
-- (matching the existing FUNCTION default), with a sink allowlist
-- generated from the api-index instead of the hand-kept registry. Known
-- non-goals (call-shaped Show()/Hide(), literal-through-local laundering,
-- stored-boolean guards, untaint-then-fall-through, non-interprocedural
-- FUNCTION consumers) are enumerated in tests/.taintrc.lua rather than
-- silently accepted.

local Parser = dofile("tests/taint/parser/init.lua")
local Annotations = dofile("tests/taint/annotations.lua")
local Config = dofile("tests/taint/config.lua")

local M = {}

--- Resolve a CallExpr's Base node to a fully-qualified name string.
--- Returns the name string, or nil if it cannot be resolved.
--- Also returns a kind: "function" (dot-access or bare) or "method" (colon-access).
--- Examples:
---   VarExpr "foo"          → "foo", "function"
---   MemberExpr "C_Spell.GetSpellCharges"  → "C_Spell.GetSpellCharges", "function"
---   MemberExpr "obj:GetMethod" (Indexer=":") → "obj:GetMethod", "method"
local function callTargetName(baseNode)
    if not baseNode then return nil, nil end
    -- F5e: a paren wrap around the resolved expression is IDENTITY in
    -- callee/base position — `(f)(x)` ≡ `f(x)`, `(obj).f` ≡ `obj.f`
    -- (multi-value truncation only matters in value-list positions,
    -- never here) — so the spelling must not defeat resolution
    -- (verified: `(pcall)(Src, 1)` escaped every pcall classification:
    -- stale-marker FP on member overwrites, unclassified secret spill
    -- FN). Inline strip: stripParens is defined later in the file.
    while type(baseNode) == "table" and baseNode.AstType == "Parentheses" do
        baseNode = baseNode.Inner
    end
    local t = baseNode.AstType
    if t == "VarExpr" then
        return baseNode.Name, "function"
    elseif t == "MemberExpr" then
        local parentName = callTargetName(baseNode.Base)
        if not parentName then return nil, nil end
        local identName = baseNode.Ident and baseNode.Ident.Data
        if not identName then return nil, nil end
        local sep = baseNode.Indexer  -- "." or ":"
        local kind = (sep == ":") and "method" or "function"
        return parentName .. sep .. identName, kind
    end
    return nil, nil
end

-- Built-in unsafe Lua sinks (calls that read a secret value at the Lua level).
-- NOTE: `type` is intentionally NOT here — it returns a fixed type-tag string
-- ("table", "number", etc.) and does not read value contents, so passing a
-- secret value to it leaks nothing.
local UNSAFE_BUILTIN_FUNCTIONS = {
    tonumber = true, tostring = true, print = true,
    pairs = true, ipairs = true, next = true,
    rawget = true, rawset = true, rawequal = true, rawlen = true,
    select = true, error = true, assert = true,
}
local CONTENT_READER_FUNCTIONS = {
    pairs = true, ipairs = true, next = true, rawget = true,
}

local COMPARISON_OPS = { ["=="]=true, ["~="]=true, ["<"]=true, [">"]=true,
    ["<="]=true, [">="]=true }
local ARITH_OPS = { ["+"]=true, ["-"]=true, ["*"]=true, ["/"]=true,
    ["%"]=true, ["^"]=true, [".."]=true }

local function isVarRef(expr)
    return type(expr) == "table" and expr.AstType == "VarExpr"
end

local stripParensFwd  -- assigned below (stripParens); needed here lexically
local chainRefKeyFwd  -- assigned below (chainRefKey); isTaintedRef needs it
local canonChainKeyFwd -- assigned below (canonChainKey); isTaintedRef needs it
local chainSegDescriptorFwd -- assigned below (chainSegDescriptor)
local constructorHasTaintedContent -- assigned with constructor helpers below

-- Per-analyze() module state; declared here so the low-level helpers below
-- can consult it lexically.  Documented and assigned at the "Per-analyze()
-- module state" comment block further down.
local registeredHandlerHits
local fnEventCtx
-- Exact member/index references proven non-secret by a path-dominating guard.
-- Bare locals continue to use taintSet clearing; this companion state exists
-- so guarding `t.f` does not unsafely clear the whole tainted table `t`.
local safeRefSet
-- Names in the CURRENT function body that are invocation-local tables
-- (round-8i): set by walkFunctionBody via collectFreshTables; nil at the
-- top level (file-scope tables are heap for every closure).
local fnFreshTables
-- Persistent-cache modeling (round-10b/10c, interprocedural): names bound
-- as params/locals in the CURRENT function (set by walkFunctionBody; nil
-- at top level). A tainted write whose chain ROOT is neither
-- invocation-fresh nor function-local lands on HEAP state that outlives
-- the call (chunk local, upvalue, global) — a persistent cache slot.
local fnLocalNames
-- Per-node lexical resolution for the CURRENT function (round-10c):
-- [VarExpr node] = binding ID for that USE — "outer" when no enclosing
-- local binds the name at that node, else a per-pass GLOBALLY UNIQUE
-- qualified ID "F<walk>:L<n>" per local binding instance (Codex catch
-- #10: qualified IDs stay valid across nested-walk inheritance, so
-- ancestry never flattens into a shared class). Not the fnLocalNames
-- union — an unrelated block-local shadow must not suppress a chunk-cache
-- write, and two sibling-block shadows are DIFFERENT tables.
local fnOuterVarNodes
-- Field-key binding provenance for the CURRENT function walk (round-10c,
-- Codex catches #3-#10). [key] = evidence CLASS or set of classes:
-- "outer" (a chunk/global-binding write or persistent seed) or a
-- qualified binding ID (a write through that exact binding, directly or
-- via capture). Real writes REPLACE the entry with their root's single
-- class (alias-rewritten keys clear to nil = legacy always-usable);
-- seeds/inheritance UNION classes (addProvClass — one key can carry chunk
-- and ancestor evidence simultaneously, the read's own binding picks).
-- nil provenance is legacy taint, always usable. Nested closures inherit
-- entries AS-IS — qualified IDs remain meaningful.
local fnKeyProvenance
-- GLOBAL per-pass maps keyed by qualified binding ID (reset in
-- M.analyze's fixpoint loop, filled by every collectOuterVarNodes walk):
--   fnBindingFresh: value is a private allocation (constructor / scalar
--     init, never rebound).
--   fnBindingValueEscaped: the VALUE escaped as a whole — bare use,
--     method-call receiver, rebind target. Capture by a closure is NOT a
--     value escape (catch #10): a captured-only fresh binding stays
--     private; closure writes through the capture flow by binding
--     IDENTITY (qualified-ID provenance/exports), not by widening.
-- bindingIsPrivate(id) = fresh and not value-escaped; a private binding
-- never exchanges cross-binding evidence (catch #4).
local fnBindingFresh
local fnBindingValueEscaped
-- Exact fields dirtied after an all-arms fresh rebind, keyed by the merged
-- binding ID.  A merged table can remain a private allocation while still
-- carrying a secret in one of its own fields.  Keeping the dirtiness per key
-- lets that field flow without admitting stale evidence for unrelated fields
-- from the table value that the rebind replaced.
local fnBindingDirtyKeys
-- VarExpr NODES inside nested closures that resolve to an ENCLOSING
-- function's local binding at the closure's exact lexical position —
-- [node] = that binding's QUALIFIED ID. Recorded by the enclosing walk's
-- collectOuterVarNodes (which has the full block-scoped stack there);
-- cumulative per pass. Such a use is an UPVALUE: its effective binding is
-- the captured one, never the chunk-level binding of the same name
-- (catches #8c/#9 — per-NODE, a later or sibling-block local does not
-- enclose).
local fnCapturedUpvalues
-- Chain keys exported by persistent writes during the current walk pass:
-- [key] = class set ("outer" for chunk-binding writes, the qualified ID
-- for captured-upvalue writes — catch #5's closure-fill flow matches the
-- parent's reads by binding identity, catch #10's unrelated shadows
-- don't). Set by M.analyze; consumed by the assignment write sites.
local fnPersistentExports
-- Fixpoint seed from previous passes: every function body starts with these
-- keys tainted, modeling the cache-hit path (read-before-write within one
-- function, split Fill/Read functions). Seeded per FUNCTION, not at chunk
-- top level — straight-line chunk code executes once, so its temporal
-- order is real and a pre-write read there is genuinely clean.
local fnPersistentSeed

-- Canonical base name for FIELD-taint keys (round-8d): inside a detected
-- handler, `local info = updateInfo` records aliasCanon[info]="updateInfo",
-- so a field written through EITHER name lands under (and is read from) ONE
-- key.  Without this, an independent field written via an alias hides from
-- reads via the original name once the gate clear removes the base-name
-- taint — provenance broke across table aliases.  Identity outside handlers
-- (ctx nil): general alias tracking stays a documented gap.
local function canonFieldBase(name)
    local ctx = fnEventCtx
    local c = ctx and ctx.aliasCanon and ctx.aliasCanon[name]
    return c or name
end

-- Is `e` an existence guard for the callee `calleeName` — a name chain equal
-- to the callee or a dotted prefix of it, or an `and`-chain of such chains
-- (`C_Spell and C_Spell.GetSpellCooldown` guarding `C_Spell.GetSpellCooldown(...)`)?
local function isExistenceGuardFor(e, calleeName)
    if stripParensFwd then e = stripParensFwd(e) end
    if type(e) ~= "table" then return false end
    if e.AstType == "BinopExpr" and e.Op == "and" then
        return isExistenceGuardFor(e.Lhs, calleeName)
            and isExistenceGuardFor(e.Rhs, calleeName)
    end
    if e.AstType ~= "VarExpr" and e.AstType ~= "MemberExpr" then return false end
    local chain = callTargetName(e)
    if not chain then return false end
    return calleeName == chain
        or calleeName:sub(1, #chain + 1) == (chain .. ".")
end

-- Deepest STABLE canonical prefix of a member/bracket chain, walking
-- rootward past volatile segments: "updateInfo.sub[i]" → "updateInfo.sub";
-- "updateInfo[j].cd" → "updateInfo".  nil when the chain has no VarExpr
-- root (call bases and the like).  Second return: the read's segment
-- descriptors beyond the returned prefix, root-first (chainSegDescriptor
-- spellings: ".field" / "[<literal>]" / "*" for volatile-or-unspellable).
local function stableChainPrefix(expr)
    local n = expr
    local segs = {}
    while type(n) == "table"
        and (n.AstType == "MemberExpr" or n.AstType == "IndexExpr") do
        segs[#segs + 1] = chainSegDescriptorFwd and chainSegDescriptorFwd(n)
            or "*"
        n = n.Base
        if stripParensFwd then n = stripParensFwd(n) end
        if type(n) ~= "table" then return nil end
        local prefix
        if n.AstType == "VarExpr" then
            local base = canonFieldBase(n.Name)
            -- Chain-alias unification (round-9f) applies to the prefix too.
            prefix = canonChainKeyFwd and canonChainKeyFwd(base) or base
        elseif chainRefKeyFwd
            and (n.AstType == "MemberExpr" or n.AstType == "IndexExpr") then
            local key, vol = chainRefKeyFwd(n)
            if key and not vol then
                prefix = canonChainKeyFwd and canonChainKeyFwd(key) or key
            end
        end
        if prefix then
            -- Collected outermost-first; flip to root-first.
            for i = 1, math.floor(#segs / 2) do
                segs[i], segs[#segs + 1 - i] = segs[#segs + 1 - i], segs[i]
            end
            return prefix, segs
        end
    end
    return nil
end

-- Split a recorded field key beyond a prefix length into segment
-- spellings: ".field" and "[<literal>]" each one segment ("[*]" is the
-- contamination-marker wildcard).  %q-quoted bracket keys may contain
-- dots/brackets — skip quoted regions (backslash escapes included).
local function splitKeySegments(key, fromPos)
    local segs, i, n = {}, fromPos, #key
    while i <= n do
        local c = key:sub(i, i)
        if c == "." then
            local j = i + 1
            while j <= n and key:sub(j, j):match("[%w_]") do j = j + 1 end
            segs[#segs + 1] = key:sub(i, j - 1)
            i = j
        elseif c == "[" then
            local j = i + 1
            if key:sub(j, j) == '"' then
                j = j + 1
                while j <= n do
                    local ch = key:sub(j, j)
                    j = j + (ch == "\\" and 2 or 1)
                    if ch == '"' then break end
                end
            end
            while j <= n and key:sub(j, j) ~= "]" do j = j + 1 end
            segs[#segs + 1] = key:sub(i, j)
            i = j + 1
        else
            i = i + 1
        end
    end
    return segs
end

-- Does a VOLATILE (variable-indexed) chain read possibly alias a RECORDED
-- tainted field key?  `updateInfo.sub[i]` can name the slot written as
-- `updateInfo.sub[1]` or `updateInfo.sub.cd` — a tainted key extending the
-- read's deepest STABLE prefix counts (round-9c; conservative, keep-the-taint
-- direction).  Walks rootward past volatile segments so `updateInfo[j].cd`
-- still checks the keys recorded under "updateInfo".
-- Do the read's segments from startIdx pair position-wise with a stable
-- spelling's segments?  Volatile read segments ("*") and the
-- contamination-marker wildcard ("[*]") match anything; stable spellings
-- must match exactly.  Requires the spelling to be no deeper than the
-- read's remainder (leading match — read segments beyond it don't
-- constrain).
local function segsMatchLeading(readSegs, startIdx, targetSegs)
    if #targetSegs > #readSegs - startIdx + 1 then return false end
    for i = 1, #targetSegs do
        local r, s = readSegs[startIdx + i - 1], targetSegs[i]
        if r ~= "*" and s ~= "[*]" and r ~= s then return false end
    end
    return true
end

-- Core of volatilePrefixTainted, recursive over LIVE chain-alias hops.
-- Direct: a recorded tainted key extending the prefix whose segments
-- leading-match the read remainder.  Alias hop: a leading portion of the
-- remainder may SPELL a chainAlias slot (equal to the prefix or extending
-- it, wildcards allowed) — the table there IS the alias target, so the
-- remaining segments re-read under the TARGET spelling, where descendant
-- writes were canonicalized (`t.alt.x = t.sub.y` sends `t.alt.x.z` writes
-- to "t.sub.y.z"; the volatile read `t[j].x.z` must find them).
-- MEMOIZED DFS (Codex catch: converging aliases exploded a clean read
-- exponentially): the walk's whole state is (prefix, startIdx) — the
-- match from a state is identical however it was reached — so `seen`
-- prunes revisits.  States are finite (alias spellings × read length),
-- which also terminates alias CYCLES; no hop cap needed.
-- Chain root VarExpr NODE (name-returning twin: chainRootName further
-- down). Early definition via stripParensFwd — consumed by the per-read
-- persistent-seed verification below and the export decision later.
local function chainRootVarNode(n)
    if stripParensFwd then n = stripParensFwd(n) end
    while type(n) == "table"
        and (n.AstType == "MemberExpr" or n.AstType == "IndexExpr") do
        n = stripParensFwd and stripParensFwd(n.Base) or n.Base
    end
    if type(n) == "table" and n.AstType == "VarExpr" then return n end
    return nil
end

-- Per-read binding-provenance verification (round-10c; Codex catches: any
-- whole-function suppression is lexically unsound, and retiring provenance
-- on a real write reopens the shadow FP). A fieldTaintSet key with
-- recorded provenance is usable evidence only when the READ's lexical
-- root resolves to the SAME binding that recorded it ("outer" seed vs
-- outer read, local write vs same-local read). nil provenance (legacy
-- taint: chunk-level writes, alias-rewritten keys) and an unresolvable
-- read root stay usable — keep-the-taint.
-- A binding is PRIVATE when its value is a fresh allocation no other name
-- can hold: constructor/scalar init, never VALUE-escaping (capture alone
-- does not count — catch #10). "outer" is never private.
local function bindingIsPrivate(id)
    return id ~= "outer"
        and fnBindingFresh ~= nil and fnBindingFresh[id] == true
        and not (fnBindingValueEscaped and fnBindingValueEscaped[id])
end

-- Provenance class algebra: an entry is a single class (string) or a SET
-- of classes. addProvClass returns a NEW value (entries are shared across
-- inherited maps — never mutate in place).
local function provMatches(prov, class)
    if type(prov) == "table" then return prov[class] == true end
    return prov == class
end
local function addProvClass(prov, class)
    if prov == nil then return class end
    if provMatches(prov, class) then return prov end
    if type(prov) == "table" then
        local merged = { [class] = true }
        for c in pairs(prov) do merged[c] = true end
        return merged
    end
    return { [prov] = true, [class] = true }
end
-- Cross-binding flow requires SOME non-private class on the evidence side.
local function provHasNonPrivateClass(prov)
    if type(prov) == "table" then
        for c in pairs(prov) do
            if not bindingIsPrivate(c) then return true end
        end
        return false
    end
    return not bindingIsPrivate(prov)
end

local function bindingDirtyKeyMatches(id, key)
    local dirty = fnBindingDirtyKeys and fnBindingDirtyKeys[id]
    if not dirty then return false end
    if dirty[key] then return true end
    for marker in pairs(dirty) do
        if marker:sub(-3) == "[*]" then
            local prefix = marker:sub(1, -4)
            if key:sub(1, #prefix + 1) == prefix .. "."
                or key:sub(1, #prefix + 1) == prefix .. "[" then
                return true
            end
        end
    end
    return false
end

-- Effective binding of a read/write root node: its local resolution, or —
-- for "outer"-resolving nodes — the captured ancestor binding recorded by
-- the enclosing walk (nil capture = true chunk/global "outer").
local function effectiveBindingId(id, node)
    if id == "outer" and fnCapturedUpvalues and node ~= nil then
        local cap = fnCapturedUpvalues[node]
        if cap then return cap end
    end
    return id
end

local function bindingEvidenceUsable(key, rootNode)
    local prov = fnKeyProvenance and fnKeyProvenance[key]
    if prov == nil then return true end
    if rootNode == nil or fnOuterVarNodes == nil then return true end
    -- Alias-canonical reads (spelled through a DIFFERENT name than the key
    -- root — `info.cd` canonicalized to "updateInfo.cd") carry no per-node
    -- identity for the key's root; legacy always-usable, mirroring the
    -- write-side rule.
    if rootNode.Name ~= key:match("^([%a_][%w_]*)") then return true end
    local id = fnOuterVarNodes[rootNode]
    if id == nil then return true end
    -- Effective binding: an "outer"-resolving node captured from an
    -- enclosing function reads THAT binding, never the chunk one of the
    -- same name (catches #8c/#9).
    local eid = effectiveBindingId(id, rootNode)
    -- Same-binding evidence always matches (a class equal to the reader's
    -- own binding — chunk seed for true-outer reads, an ancestor's writes
    -- for its captured upvalue reads, this function's own writes).
    if provMatches(prov, eid) then return true end
    -- Cross-binding evidence flows only between bindings that could name
    -- ONE shared heap table: a private allocation on EITHER side breaks
    -- the aliasing possibility (catches #3/#4/#10 — outer or escaped
    -- writes never taint a fresh shadow; a captured-only fresh binding
    -- stays private; escaped write vs OUTER read stays usable, round-8h).
    if bindingIsPrivate(eid) then
        return bindingDirtyKeyMatches(eid, key)
    end
    return provHasNonPrivateClass(prov)
end

local function refHasTaintedDescendant(expr, taintSet, fieldTaintSet, registry)
    expr = stripParensFwd and stripParensFwd(expr) or expr
    if type(expr) == "table" and expr.AstType == "ConstructorExpr" then
        return constructorHasTaintedContent
            and constructorHasTaintedContent(expr, taintSet, fieldTaintSet, registry)
    end
    if not chainRefKeyFwd then return false end
    local raw, volatile = chainRefKeyFwd(expr)
    local prefix
    if raw and not volatile then
        prefix = canonChainKeyFwd and canonChainKeyFwd(raw) or raw
    else
        prefix = stableChainPrefix(expr)
    end
    if not prefix then return false end
    local rootNode = chainRootVarNode(expr)
    local dot, bracket = prefix .. ".", prefix .. "["
    for key, value in pairs(fieldTaintSet or {}) do
        if value and (key:sub(1, #dot) == dot or key:sub(1, #bracket) == bracket)
            and bindingEvidenceUsable(key, rootNode) then
            return true
        end
    end
    return false
end

local function wildcardChainTainted(prefix, readSegs, startIdx, fieldTaintSet,
        seen, rootNode)
    local state = prefix .. "\1" .. startIdx
    if seen[state] then return false end
    seen[state] = true
    local pdot, pbr = prefix .. ".", prefix .. "["
    for k, v in pairs(fieldTaintSet) do
        if v and (k:sub(1, #pdot) == pdot or k:sub(1, #pbr) == pbr)
            and bindingEvidenceUsable(k, rootNode)
            and segsMatchLeading(readSegs, startIdx,
                splitKeySegments(k, #prefix + 1))
        then
            return true
        end
    end
    local ctx = fnEventCtx
    if not ctx then return false end
    local function slotSegsFor(slot)
        if slot == prefix then return {} end
        if slot:sub(1, #pdot) == pdot or slot:sub(1, #pbr) == pbr then
            return splitKeySegments(slot, #prefix + 1)
        end
        return nil
    end
    for slot, tgt in pairs(ctx.chainAlias or {}) do
        if tgt ~= slot then
            local slotSegs = slotSegsFor(slot)
            if slotSegs and segsMatchLeading(readSegs, startIdx, slotSegs)
                and wildcardChainTainted(tgt, readSegs,
                    startIdx + #slotSegs, fieldTaintSet, seen, nil) then
                return true
            end
        end
    end
    -- MAY-alias hops (round-10d): merge-dropped conditional links bridge
    -- volatile reads the same way LIVE links do — `while X do h = {cache
    -- = c} end; c[1] = S(); h.cache[k]` may read the secret slot. The
    -- memoized `seen` bounds converging/cyclic may-links exactly like
    -- live-alias cycles.
    for slot, tgts in pairs(ctx.chainAliasMay or {}) do
        local slotSegs = slotSegsFor(slot)
        if slotSegs and segsMatchLeading(readSegs, startIdx, slotSegs) then
            for tgt in pairs(tgts) do
                if tgt ~= slot and wildcardChainTainted(tgt, readSegs,
                        startIdx + #slotSegs, fieldTaintSet, seen, nil) then
                    return true
                end
            end
        end
    end
    return false
end

-- Does a VOLATILE (variable-indexed) chain read possibly alias a RECORDED
-- tainted field key?  `updateInfo.sub[i]` can name the slot written as
-- `updateInfo.sub[1]` or `updateInfo.sub.cd` — a tainted key extending the
-- read's deepest STABLE prefix counts (round-9c; conservative, keep-the-taint
-- direction).  Walks rootward past volatile segments so `updateInfo[j].cd`
-- still checks the keys recorded under "updateInfo".
-- SEGMENT-MATCHED (round-9m): stable segments must agree position-wise
-- (`t[j].x` never aliases "t.sub.y" ABSENT aliases: j may be "sub" but
-- .x ≠ .y), a read SHALLOWER than the key yields only an ancestor
-- container reference (never a secret value), a read at key depth may BE
-- the slot and a deeper read passes THROUGH it (indexing a secret throws).
-- ALIAS-AWARE (round-9n): live chainAlias slots bridge differently spelled
-- paths to one table, so the match recurses through them (see
-- wildcardChainTainted).
local function volatilePrefixTainted(expr, fieldTaintSet)
    local prefix, readSegs = stableChainPrefix(expr)
    if not prefix then return false end
    return wildcardChainTainted(prefix, readSegs, 1, fieldTaintSet, {},
        chainRootVarNode(expr))
end

-- Definitely-CONTENT-clean RHS shapes for the clean-replacement descendant
-- sweep (round-9e): an EMPTY constructor or a scalar literal cannot carry
-- tainted fields.  An untainted VARIABLE copy can (`t.sub = t2` — t2's
-- tainted fields/markers are keyed under t2's own root and become readable
-- through t.sub), and so can a call result or a non-empty constructor — for
-- those only the exact slot key clears.
local function isContentCleanExpr(e)
    if stripParensFwd then e = stripParensFwd(e) end
    if type(e) ~= "table" then return false end
    local t = e.AstType
    if t == "ConstructorExpr" then
        return not (e.EntryList and #e.EntryList > 0)
    end
    return t == "NilExpr" or t == "NumberExpr"
        or t == "StringExpr" or t == "BooleanExpr"
end

-- Untracked-slot CONTAMINATION marker (round-9d): a keyless (volatile /
-- unkeyable) write of a tainted value records "<stablePrefix>[*]" in
-- fieldTaintSet — "[*]" cannot collide with real keys (stable bracket keys
-- are numbers or %q-quoted strings).  fieldTaintSet is HEAP state
-- (round-8h), so the contamination survives terminating branches and later
-- invocations; the fresh-table rollback exception applies via the key's
-- root like any other field key.  Marked independent so aura-gate clears
-- never bless it.  Stable reads under a contaminated prefix must consult
-- the markers (volatile reads already match them through the prefix scan).
-- STRICT descendants only: the marker says some unknown SLOT under the
-- prefix is tainted — a read of the prefix itself yields the container
-- table reference, which is never a secret value (truth-tests and %s on
-- it are safe; a VarExpr-rooted container read never consulted markers
-- either).
local function contaminationMarkerTainted(canonKey, fieldTaintSet, rootNode)
    for k, v in pairs(fieldTaintSet) do
        if v and k:sub(-3) == "[*]" and bindingEvidenceUsable(k, rootNode) then
            local p = k:sub(1, -4)
            if canonKey:sub(1, #p + 1) == p .. "."
                or canonKey:sub(1, #p + 1) == p .. "[" then
                return true
            end
        end
    end
    return false
end

-- PERSISTENT may-alias registry (round-10d, Codex catch: conditional
-- constructor aliases hid secret-tainted paths). A merge that finds alias
-- DISAGREEMENT with no taint in sight used to drop the link entirely — a
-- LATER secret write through one target was then invisible through the
-- slot spelling (`while X do h = { cache = c } end; c.foo = S();
-- h.cache.foo` read clean). ctx.chainAliasMay[spelling] = {target=true}
-- keeps the may-alias FACT; reads consult it after exact keys and
-- contamination markers miss, re-spelling the read's remainder under each
-- may-target. Structural-prefix indexing avoids full-graph scans and a
-- visited-key set terminates converging/cyclic graphs without a hop cap.
-- Monotone within a walk — only parameter shadowing prunes; a
-- stale link after a definite overwrite reads conservative
-- (keep-the-taint), mirroring stale-keep for direct keys.
local function invalidateMayAliasCache(ctx)
    ctx = ctx or fnEventCtx
    if not ctx then return end
    ctx.mayAliasGeneration = (ctx.mayAliasGeneration or 0) + 1
    ctx.mayAliasQueryCache = {}
    ctx.mayAliasRelevantRoots = {}
end

local function mayAliasEdgeVersion(ctx, from, to)
    local versions = ctx and ctx.mayAliasEdgeVersions
    return versions and versions[from] and versions[from][to] or 0
end

local function refreshMayAliasEdge(ctx, from, to, reasserted)
    if not (ctx and from and to) then return 0 end
    local allocator = ctx.mayAliasEdgeAllocator or { serial = 0 }
    ctx.mayAliasEdgeAllocator = allocator
    local current = mayAliasEdgeVersion(ctx, from, to)
    -- Flow merges can temporarily drop an edge and then materialize the same
    -- disagreement again on the next fixpoint pass. Reuse that edge's last
    -- allocated epoch so the abstract state converges.
    if current == 0 then
        local historical = allocator.edgeVersions
            and allocator.edgeVersions[from]
            and allocator.edgeVersions[from][to] or 0
        if historical > 0 then
            ctx.mayAliasEdgeVersions = ctx.mayAliasEdgeVersions or {}
            local versions = ctx.mayAliasEdgeVersions[from]
            if not versions then
                versions = {}
                ctx.mayAliasEdgeVersions[from] = versions
            end
            versions[to] = historical
            current = historical
        end
    end
    if current > 0 then
        -- A syntactic write of the SAME edge is a new fact after any prior
        -- concrete overwrite, but it need not mint an unbounded epoch:
        -- remove only this target's old kill and reuse the edge identity.
        -- Other wildcard targets and unrelated concrete slots stay blocked.
        if reasserted then
            for key, slots in pairs(ctx.mayAliasCleanEdges or {}) do
                local targets = slots[from]
                if targets then
                    targets[to] = nil
                    if next(targets) == nil then slots[from] = nil end
                end
                if next(slots) == nil then
                    ctx.mayAliasCleanEdges[key] = nil
                end
            end
        end
        return current
    end
    -- New edges allocate exactly once; same-edge reassertions above reuse
    -- their identity and therefore remain finite under loop transfer.
    allocator.serial = allocator.serial + 1
    ctx.mayAliasEdgeVersions = ctx.mayAliasEdgeVersions or {}
    local versions = ctx.mayAliasEdgeVersions[from]
    if not versions then
        versions = {}
        ctx.mayAliasEdgeVersions[from] = versions
    end
    versions[to] = allocator.serial
    allocator.edgeVersions = allocator.edgeVersions or {}
    local history = allocator.edgeVersions[from]
    if not history then
        history = {}
        allocator.edgeVersions[from] = history
    end
    history[to] = allocator.serial
    return allocator.serial
end

local function wildcardPatternCoversKey(pattern, concrete)
    local patternRoot = pattern and pattern:match("^([%a_][%w_]*)")
    local concreteRoot = concrete and concrete:match("^([%a_][%w_]*)")
    if not patternRoot or patternRoot ~= concreteRoot then return false end
    local patternSegs = splitKeySegments(pattern, #patternRoot + 1)
    local concreteSegs = splitKeySegments(concrete, #concreteRoot + 1)
    if #patternSegs > #concreteSegs then return false end
    for i, segment in ipairs(patternSegs) do
        if segment ~= "[*]" and segment ~= concreteSegs[i] then
            return false
        end
    end
    return true
end

local function markMayAliasConcreteClean(key, subtree)
    local ctx = fnEventCtx
    if not (ctx and key) then return end
    if subtree then
        ctx.mayAliasCleanSubtree = ctx.mayAliasCleanSubtree or {}
        ctx.mayAliasCleanSubtree[key] = true
    else
        ctx.mayAliasCleanExact = ctx.mayAliasCleanExact or {}
        ctx.mayAliasCleanExact[key] = true
    end
    local cutoffs = {}
    for slot, targets in pairs(ctx.chainAliasMay or {}) do
        if slot:find("[*]", 1, true)
            and wildcardPatternCoversKey(slot, key) then
            local targetCutoffs
            for target in pairs(targets) do
                local version = mayAliasEdgeVersion(ctx, slot, target)
                if version > 0 then
                    targetCutoffs = targetCutoffs or {}
                    targetCutoffs[target] = version
                end
            end
            if targetCutoffs then cutoffs[slot] = targetCutoffs end
        end
    end
    ctx.mayAliasCleanEdges = ctx.mayAliasCleanEdges or {}
    ctx.mayAliasCleanEdges[key] = cutoffs
    invalidateMayAliasCache(ctx)
end

local function mayAliasEdgeBlocked(key, wildcardSlot, target, version)
    local ctx = fnEventCtx
    if not (ctx and key and wildcardSlot and target) then return false end
    for prefix, cutoffs in pairs(ctx.mayAliasCleanEdges or {}) do
        local covers = key == prefix
            or key:sub(1, #prefix + 1) == prefix .. "."
            or key:sub(1, #prefix + 1) == prefix .. "["
        local targetCutoffs = covers and cutoffs[wildcardSlot]
        local cutoff = targetCutoffs and targetCutoffs[target]
        if cutoff and version <= cutoff then
            return true
        end
    end
    return false
end

local function wildcardKeyMatches(pattern, concrete)
    local patternRoot = pattern and pattern:match("^([%a_][%w_]*)")
    local concreteRoot = concrete and concrete:match("^([%a_][%w_]*)")
    if not patternRoot or patternRoot ~= concreteRoot then return false end
    local patternSegs = splitKeySegments(pattern, #patternRoot + 1)
    local concreteSegs = splitKeySegments(concrete, #concreteRoot + 1)
    if #patternSegs ~= #concreteSegs then return false end
    for i, segment in ipairs(patternSegs) do
        if segment ~= "[*]" and concreteSegs[i] ~= "[*]"
            and segment ~= concreteSegs[i] then
            return false
        end
    end
    return true
end

local function mayAliasTainted(canonKey, fieldTaintSet, seen)
    local ctx = fnEventCtx
    local may = ctx and ctx.chainAliasMay
    if not may or canonKey:sub(1, 1) == "~" then return false end
    local generation = ctx.mayAliasGeneration or 0
    local cacheable = seen == nil
    if cacheable then
        local cached = ctx.mayAliasQueryCache
            and ctx.mayAliasQueryCache[canonKey]
        if cached and cached.generation == generation then
            return cached.value
        end
    end
    seen = seen or {}
    -- A reverse traversal from a concrete target into a wildcard spelling
    -- must retain WHICH temporal edge selected that wildcard. Otherwise a
    -- cycle can jump between mutually-exclusive MAY targets
    -- (`d -> h[*] -> c`) and resurrect an edge a strong overwrite blocked.
    -- Constraints are immutable per work item and keyed by wildcard slot.
    local function addConstraint(constraints, slot, target, version)
        local prior = constraints and constraints[slot]
        if prior and prior.target ~= target then return nil end
        if prior and prior.version == version then return constraints end
        local copy = {}
        for key, value in pairs(constraints or {}) do
            copy[key] = {
                target = value.target,
                version = value.version,
            }
        end
        copy[slot] = { target = target, version = version }
        return copy
    end
    local function constraintsAllow(constraints, concrete)
        for slot, edge in pairs(constraints or {}) do
            if mayAliasEdgeBlocked(concrete, slot, edge.target,
                edge.version) then
                return false
            end
        end
        return true
    end
    local function stateId(key, constraints)
        local parts = {}
        for slot, edge in pairs(constraints or {}) do
            parts[#parts + 1] = slot .. "\1" .. edge.target
                .. "\1" .. tostring(edge.version)
        end
        table.sort(parts)
        return key .. "\2" .. table.concat(parts, "\2")
    end
    local function finish(value)
        if cacheable then
            ctx.mayAliasQueryCache = ctx.mayAliasQueryCache or {}
            ctx.mayAliasQueryCache[canonKey] = {
                generation = generation,
                value = value,
            }
        end
        return value
    end
    local function keyDepth(key)
        local root = key and key:match("^([%a_][%w_]*)")
        if not root then return 0 end
        return 1 + #splitKeySegments(key, #root + 1)
    end
    -- Prefix-rewrite cycles can have positive net growth (`a -> b.x`,
    -- `b -> a`), yielding infinitely many concrete spellings even though the
    -- alias and taint lattices are finite.  No spelling deeper than every
    -- query/rule/taint key plus one largest rule can be the first useful hit:
    -- any longer excursion must traverse a growth cycle that can be removed
    -- before the same finite target is reached.  This is a structural state
    -- bound, not the old arbitrary hop cap; long acyclic alias chains remain
    -- fully traversable.
    local maxRelevantDepth, maxRuleDepth = keyDepth(canonKey), 0
    for key, value in pairs(fieldTaintSet) do
        if value then
            local depth = keyDepth(key)
            if depth > maxRelevantDepth then maxRelevantDepth = depth end
        end
    end
    for slot, targets in pairs(may) do
        local slotDepth = keyDepth(slot)
        if slotDepth > maxRelevantDepth then maxRelevantDepth = slotDepth end
        if slotDepth > maxRuleDepth then maxRuleDepth = slotDepth end
        for target in pairs(targets) do
            local targetDepth = keyDepth(target)
            if targetDepth > maxRelevantDepth then
                maxRelevantDepth = targetDepth
            end
            if targetDepth > maxRuleDepth then maxRuleDepth = targetDepth end
        end
    end
    local maxDepth = maxRelevantDepth + maxRuleDepth
    local pending, cursor = {
        { key = canonKey, constraints = {} },
    }, 1
    while cursor <= #pending do
        local state = pending[cursor]
        local current = state.key
        local constraints = state.constraints
        cursor = cursor + 1
        local currentStateId = stateId(current, constraints)
        if not seen[currentStateId] then
            seen[currentStateId] = true
            local currentRoot = current:match("^([%a_][%w_]*)")
            if currentRoot then
                ctx.mayAliasRelevantRoots =
                    ctx.mayAliasRelevantRoots or {}
                ctx.mayAliasRelevantRoots[currentRoot] = true
            end

            if fieldTaintSet[current] == true then return finish(true) end
            if current:find("[*]", 1, true) then
                for key, value in pairs(fieldTaintSet) do
                    if value and wildcardKeyMatches(current, key)
                        and constraintsAllow(constraints, key) then
                        return finish(true)
                    end
                end
            end
            if contaminationMarkerTainted(current, fieldTaintSet, nil) then
                return finish(true)
            end

            -- Only ancestor spellings of the read can be alias slots.
            -- Enumerating structural prefixes turns the old full-map scan at
            -- every hop into O(chain depth) lookups and avoids quoted bracket
            -- contents being mistaken for separators.  The explicit
            -- worklist handles arbitrarily deep graphs without consuming the
            -- Lua/C call stack.
            local root = current:match("^([%a_][%w_]*)")
            if root then
                local segments = splitKeySegments(current, #root + 1)
                local prefixes = {
                    { key = root, consumed = 0 },
                }
                local prefix = root
                for index, seg in ipairs(segments) do
                    prefix = prefix .. seg
                    prefixes[#prefixes + 1] = {
                        key = prefix,
                        consumed = index,
                    }
                end
                local function enqueueTargets(tgts, rest, edgeFrom,
                        concreteKey)
                    if tgts then
                        for tgt in pairs(tgts) do
                            local allowed = true
                            local nextConstraints = constraints
                            if edgeFrom
                                and edgeFrom:find("[*]", 1, true) then
                                local version = mayAliasEdgeVersion(
                                    ctx, edgeFrom, tgt)
                                local required = constraints[edgeFrom]
                                if required and required.target ~= tgt then
                                    allowed = false
                                elseif concreteKey and mayAliasEdgeBlocked(
                                    concreteKey, edgeFrom, tgt, version) then
                                    allowed = false
                                else
                                    nextConstraints = addConstraint(
                                        constraints, edgeFrom, tgt, version)
                                    if not nextConstraints then
                                        allowed = false
                                    end
                                end
                            elseif edgeFrom
                                and tgt:find("[*]", 1, true) then
                                nextConstraints = addConstraint(
                                    constraints, tgt, edgeFrom,
                                    mayAliasEdgeVersion(
                                        ctx, tgt, edgeFrom))
                                if not nextConstraints then
                                    allowed = false
                                end
                            end
                            local rekey = tgt .. rest
                            local nextId = stateId(rekey, nextConstraints)
                            if allowed and rekey ~= current
                                and not seen[nextId]
                                and keyDepth(rekey) <= maxDepth then
                                pending[#pending + 1] = {
                                    key = rekey,
                                    constraints = nextConstraints,
                                }
                            end
                        end
                    end
                end
                for _, entry in ipairs(prefixes) do
                    local slot = entry.key
                    local live = ctx.chainAlias and ctx.chainAlias[slot]
                    if live then
                        enqueueTargets(
                            { [live] = true }, current:sub(#slot + 1))
                    end
                    -- Exact table aliases are identities, not one-way value
                    -- copies. A MAY hop can land on the TARGET spelling and
                    -- must still walk back through a live slot
                    -- (`h[*] -> root`, `root.slot -> c`, then a write through
                    -- `h.ab.slot` must be visible through `c`).
                    for liveSlot, target in pairs(ctx.chainAlias or {}) do
                        if target == slot
                            then enqueueTargets(
                                { [liveSlot] = true },
                                current:sub(#slot + 1))
                        end
                    end
                    if slot:find("[*]", 1, true) and ctx.chainAlias then
                        for liveSlot, target in pairs(ctx.chainAlias) do
                            local concrete = liveSlot
                                .. current:sub(#slot + 1)
                            if wildcardKeyMatches(slot, liveSlot)
                                and constraintsAllow(
                                    constraints, concrete) then
                                enqueueTargets(
                                    { [target] = true },
                                    table.concat(segments, "",
                                        entry.consumed + 1))
                            end
                        end
                    end
                    enqueueTargets(may[slot],
                        current:sub(#slot + 1), slot)
                    -- A keyless write records the table VALUE stored in one
                    -- unknown child slot (`h[*] -> c`). A later stable read
                    -- may select that slot, so consume exactly one read
                    -- segment before continuing under the target:
                    -- `h.ab.foo` rekeys to `c.foo`, not `c.ab.foo`.
                    if entry.consumed < #segments then
                        local rest = table.concat(
                            segments, "", entry.consumed + 2)
                        local wildcardSlot = slot .. "[*]"
                        enqueueTargets(may[wildcardSlot], rest,
                            wildcardSlot, current)
                    end
                end
            end
        end
    end
    return finish(false)
end

-- Returns true if expr is a tainted local OR a read of a tainted field (t.k).
-- fieldTaintSet is keyed by "<tableLocalName>.<field>".
-- Also handles deep chains: if any ancestor in the MemberExpr chain is a tainted
-- local, the whole chain is considered tainted (conservative over-approximation).
-- Content reads also consult the base name's alias-CANONICAL taint: an
-- untracked-slot write re-taints the canonical root, and reads through any
-- alias of that table must see it (round-9c).
-- Clean-field whitelist: when registry:isCleanField(<field>) is true, reading
-- that field from any base is treated as non-secret (e.g. SpellCooldownInfo.
-- isOnGCD is always a clean boolean per Blizzard contract).
local function isTaintedRef(expr, taintSet, fieldTaintSet, registry)
    if type(expr) ~= "table" then return false end
    if safeRefSet and chainRefKeyFwd
        and (expr.AstType == "MemberExpr" or expr.AstType == "IndexExpr") then
        local rawKey = chainRefKeyFwd(expr)
        if rawKey then
            local key = canonChainKeyFwd and canonChainKeyFwd(rawKey) or rawKey
            if safeRefSet[key] then return false end
        end
    end
    if expr.AstType == "VarExpr" then
        return taintSet[expr.Name] == true
    end
    if expr.AstType == "MemberExpr"
       and expr.Indexer == "."
       and expr.Ident and expr.Ident.Data then
        local field = expr.Ident.Data
        -- Clean-field whitelist applies regardless of base shape.
        if registry and registry.isCleanField and registry:isCleanField(field) then
            return false
        end
        if expr.Base and expr.Base.AstType == "VarExpr" then
            -- Field-write-then-read tracking (alias-canonical base round-8d,
            -- chain-alias unification round-9f). Seed-only keys additionally
            -- verify the read's root resolves outer (round-10c).
            local canonBase = canonFieldBase(expr.Base.Name)
            local key = canonBase .. "." .. field
            if canonChainKeyFwd then key = canonChainKeyFwd(key) end
            if fieldTaintSet[key] == true
                and bindingEvidenceUsable(key, expr.Base) then
                return true
            end
            if contaminationMarkerTainted(key, fieldTaintSet, expr.Base) then return true end
            if mayAliasTainted(key, fieldTaintSet) then return true end
            -- Read of any field from a tainted base local — the CANONICAL
            -- name too (reads via other aliases must see canon-name taint,
            -- round-9c).
            if taintSet[expr.Base.Name] == true
                or taintSet[canonBase] == true then
                return true
            end
        elseif expr.Base and (expr.Base.AstType == "MemberExpr"
                or expr.Base.AstType == "IndexExpr") then
            -- Deep-chain field-write-then-read (round-9): a write recorded
            -- under the FULL canonical chain key ("updateInfo.sub.cd") is
            -- invisible to the base recursion below (which drops the outer
            -- field) — check it first.  A VOLATILE chain may alias any
            -- recorded key under its stable prefix (round-9c); a STABLE
            -- chain under a contamination marker is possibly the untracked
            -- slot (round-9d).
            if chainRefKeyFwd then
                local rawKey, volatile = chainRefKeyFwd(expr)
                if rawKey and not volatile then
                    local key = canonChainKeyFwd and canonChainKeyFwd(rawKey) or rawKey
                    local rootNode = chainRootVarNode(expr)
                    if fieldTaintSet[key] == true
                        and bindingEvidenceUsable(key, rootNode) then
                        return true
                    end
                    if contaminationMarkerTainted(key, fieldTaintSet, rootNode) then return true end
                    if mayAliasTainted(key, fieldTaintSet) then return true end
                elseif volatilePrefixTainted(expr, fieldTaintSet) then
                    return true
                end
            end
            -- Recurse: deep chain (e.g. tainted.sub.field)
            return isTaintedRef(expr.Base, taintSet, fieldTaintSet, registry)
        end
    end
    if expr.AstType == "IndexExpr" then
        -- Bracketed reads (round-9b): STABLE keys ("t.sub[1]", 't.sub["k"]' —
        -- identifier string keys fold to the dot form, so bracket writes and
        -- dot reads unify) participate in field-write-then-read tracking via
        -- their canonical chain key.  A VOLATILE key may alias ANY recorded
        -- key under its stable prefix (round-9c); stable keys also consult
        -- contamination markers (round-9d).  The base recursion keeps
        -- tainted-root propagation for every bracket shape.
        if chainRefKeyFwd then
            local rawKey, volatile = chainRefKeyFwd(expr)
            if rawKey and not volatile then
                local key = canonChainKeyFwd and canonChainKeyFwd(rawKey) or rawKey
                -- Clean-field whitelist parity with the dotted path
                -- (round-9d): `info["isOnGCD"]` folds to "info.isOnGCD" —
                -- a trailing identifier segment that is a registered clean
                -- field reads clean here too.
                local lastField = key:match("%.([%a_][%w_]*)$")
                if lastField and registry and registry.isCleanField
                    and registry:isCleanField(lastField) then
                    return false
                end
                local rootNode = chainRootVarNode(expr)
                if fieldTaintSet[key] == true
                    and bindingEvidenceUsable(key, rootNode) then
                    return true
                end
                if contaminationMarkerTainted(key, fieldTaintSet, rootNode) then return true end
                if mayAliasTainted(key, fieldTaintSet) then return true end
            elseif volatilePrefixTainted(expr, fieldTaintSet) then
                return true
            end
        end
        if expr.Base and expr.Base.AstType == "VarExpr" then
            -- Canon-name check for direct bracket reads off an alias
            -- (`b[k]` after an untracked write via another alias).
            return taintSet[expr.Base.Name] == true
                or taintSet[canonFieldBase(expr.Base.Name)] == true
        end
        return isTaintedRef(expr.Base, taintSet, fieldTaintSet, registry)
    end
    return false
end

-- Extract the trailing method/field name from a qualified name produced by
-- callTargetName. The separator is "." for dot-access and ":" for colon-access,
-- so we split on the last "." or ":" character.
-- Examples: "cd:SetCooldownFromDurationObject" → "SetCooldownFromDurationObject"
--           "C_StringUtil.RoundToNearestString" → "RoundToNearestString"
--           "bare"                              → "bare"
local function getMethodNameFromQualified(qualified)
    local lastSep = qualified:match(".*[.:]()") -- () captures position after separator
    if lastSep then return qualified:sub(lastSep) end
    return qualified
end

--- Get line number from an AST node. AST nodes store line info in Tokens[1].Line.
local function nodeLine(node)
    return (node.Tokens and node.Tokens[1] and node.Tokens[1].Line) or 0
end

local function nodeLocation(node)
    local token = node and node.Tokens and node.Tokens[1]
    return token and token.Line or 0, token and token.Char or 0
end

--- Emit a finding into `findings`. Severity defaults to advisory; later tasks
--- promote to strict by file path.
local function emit(findings, filePath, line, col, sink, sourceFunc, message)
    findings[#findings + 1] = {
        file = filePath, line = line or 0, col = col or 1,
        severity = "advisory",
        source_function = sourceFunc or "<unknown>",
        sink = sink, message = message or "",
        suppressed = false, suppression_reason = nil,
    }
end

-- Forward declarations so expression and statement walkers can call each other.
local walkExpr
local walkStatements
local resolveIntraFileFunctionSummary
local detectUnsafeProbeOrder  -- defined with the round-7e proof machinery below
local purgeMutableSafeRefs
-- Round-8: the taint walk consults the precondition-scan machinery (gate
-- dominance, terminating bodies) and the file-scope alias maps; these are
-- defined later in the file, so forward-declare.
local bodyTerminates
local stmtEndsFlowCore -- assigned beside bodyTerminates (flow view)
local restrictedImpliesTrue
-- Does a statement end flow in the CURRENT block on every path?
-- bodyTerminates' terminator set (return / error() / all-arms-return if /
-- terminating do — the error-shadowing forfeit rides along) PLUS loop
-- exits: a bare break, an all-arms-break if, a do-block ending in a
-- break, and loops whose exit is provably never reached (break-free
-- repeat with a flow-ending body or `until false`; break-free `while
-- true`) — round-10d follow-ups 5-9. Statements after a flow-ending
-- statement are dead code. ONE implementation: the logic lives inside
-- bodyTerminates behind its flowMode parameter (see the assignment
-- below), because walkStatements sits at Lua 5.1's 60-upvalue cap and
-- can only reach the flow view through a name it already captures —
-- earlier lockstep-copy attempts drifted within one session. This
-- wrapper serves everything with upvalue headroom
-- (collectRegisteredHandlers' statement walk — a DEAD RegisterEvent
-- must not link a live handler).
local function stmtEndsFlow(stmt)
    return bodyTerminates({ Body = { stmt } }, true)
end
-- File-scope aliases (map/ns/binds/poisoned) built in M.analyze before the
-- taint walk; nil when alias collection did not run. Same per-analyze()
-- module-state pattern as fnEventCtx below.
local fnAliases
-- Does the chunk ever REBIND `error` (local, assignment, parameter, function
-- name, for-variable, or a global-environment write — `_G.error = f`,
-- rawset, getfenv/setfenv)?  Set per analyze() by chunkShadowsError.  Terminator
-- recognition in bodyTerminates is PROTECTION-GRANTING (taint/provenance
-- roll-back of terminating branches, gate/guard bail dominance), and a
-- shadowed error() may return normally and fall through — so it must forfeit
-- terminator status.  Cannot ride aliases.binds: that map only exists when
-- the needAliases pre-filter fires, but the taint roll-back protects files
-- that never mention a gate or guard.
local fnErrorShadowed

-- Alias-aware guard lookup (round-8): `local isv = issecretvalue; isv(x)`
-- must count as a probe. Guard recognition is PROTECTION-GRANTING (it
-- suppresses findings), so — exactly like isGateName for restriction gates —
-- a name the file ever binds to anything else is poisoned and grants nothing.
local function isGuardName(name, registry, aliases)
    if not name then return false end
    aliases = aliases or fnAliases
    if registry:isGuard(name) then
        -- Round-8 discipline extends to the DIRECT hit (stop-gate): a guard
        -- NAME the file rebinds to anything other than itself is shadowed
        -- and takes no DIRECT credit. Self-canonical bindings are the
        -- legitimate upvalue-cache idioms — bare (`local issecretvalue =
        -- issecretvalue`) or _G-qualified (normalized in harvest);
        -- binds[name] == false records a non-canonical binding. A rebound
        -- name FALLS THROUGH rather than failing outright: the binding may
        -- itself be a registered guard alias (`local IsSecretValue =
        -- Helpers.IsSecretValue`), which the map path below credits — an
        -- early false here revoked exactly that idiom repo-wide.
        -- Scope: BUILTIN guard names only. Custom guards (.taintrc
        -- extra_guards) are audited wrapper FUNCTIONS — their defining file
        -- binds the name to a function literal by construction.
        if not registry:isBuiltinGuard(name) then return true end
        local binds = aliases and aliases.binds
        if not (binds and binds[name] ~= nil
            and binds[name] ~= name
            and binds[name] ~= ("_G." .. name)) then
            return true
        end
    end
    if not aliases then return false end
    local poisoned = aliases.poisoned or {}
    if aliases.map[name] then
        return (not poisoned[name]) and registry:isGuard(aliases.map[name])
    end
    local prefix, rest = name:match("^([%w_]+)([.:].+)$")
    if prefix and aliases.ns[prefix] then
        return (not poisoned[prefix])
            and registry:isGuard(aliases.ns[prefix] .. rest)
    end
    return false
end

-- Method-form guard lookup for the consumer exemption (obj:IsSecretValue(x)).
-- Same poison discipline as isGuardName: the exemption is PROTECTION-GRANTING,
-- so a bare method name the file ever binds to anything else is poisoned and
-- grants nothing — otherwise `local IsSecretValue = <impostor>` would smuggle
-- a shadowed member call past the consumer classifier.
local function isGuardMethodName(name, registry, aliases)
    -- RECEIVER-AWARE only (stop-gate round 2): `Helpers:IsSecretValue(x)`
    -- maps to the registered dotted guard "Helpers.IsSecretValue". A bare
    -- method-name match would exempt ANY object's same-named method —
    -- protection-granting paths get no such benefit of the doubt. Unnamed /
    -- complex receivers resolve to no qualified name and are never exempt.
    if not name or not name:find(":", 1, true) then return false end
    local prefix = name:match("^([%w_]+)[.:]")
    if not prefix then return false end
    aliases = aliases or fnAliases
    local poisoned = aliases and aliases.poisoned or {}
    if poisoned[prefix] then return false end
    -- Receiver must be the canonical namespace itself (possibly cached
    -- self-canonically) or a registered ns-alias of it.
    local dotted = name:gsub(":", ".", 1)
    if registry:isGuard(dotted) then
        local binds = aliases and aliases.binds
        if binds and binds[prefix] ~= nil
            and binds[prefix] ~= prefix
            and binds[prefix] ~= ("_G." .. prefix) then return false end
        return true
    end
    if aliases and aliases.ns[prefix] then
        local resolved = (aliases.ns[prefix] .. name:match("^[%w_]+([.:].+)$")):gsub(":", ".", 1)
        return registry:isGuard(resolved)
    end
    return false
end

-- Element-secret container calls (round-23): the RESULT is a readable
-- container whose elements secretize (conditionalSecretContents).
-- Permissive alias resolution (finding-emission tier, like the
-- precondition scan's map/ns use — not protection-granting).
local function isElementSecretCallName(name, registry)
    if not name then return false end
    if registry:isElementSecretFunction(name) then return true end
    local aliases = fnAliases
    if not aliases then return false end
    if aliases.map[name] then
        return registry:isElementSecretFunction(aliases.map[name])
    end
    local prefix, rest = name:match("^([%w_]+)([.:].+)$")
    if prefix and aliases.ns[prefix] then
        return registry:isElementSecretFunction(aliases.ns[prefix] .. rest)
    end
    return false
end

local function stripParens(expr)
    while type(expr) == "table" and expr.AstType == "Parentheses" do
        expr = expr.Inner
    end
    return expr
end
stripParensFwd = stripParens

-- VALUE-flow taint: like isTaintedRef, but follows short-circuit and/or —
-- `info and info.f` YIELDS the tainted field, so a VALUE consumer
-- (assignment, unsafe-builtin argument, comparison/arith operand) sees taint
-- even though the binop itself is an exempt existence test (round-6c:
-- `print(info and info.f)` and `local v = info and info.f` were reproducible
-- false negatives after the round-6b binop exemptions).
--
-- `X and Y` yields value(Y) when everything is truthy, or the FALSY value of
-- X. A falsy secret (secret-false boolean) is still secret, so lhs taint
-- must flow (round-6d: `isActive and Wrap(isActive)` leaked unflagged).
-- There is NO sound type shortcut here: an index of X inside Y
-- (`chargeInfo and Decode(chargeInfo.isActive)`) proves nothing about the
-- falsy path — the index only evaluates when X is TRUTHY, so a secret-false
-- X short-circuits straight past it (round-6d follow-up: the struct-
-- assertion exception was itself a reproducible false negative). Sites where
-- the API contract guarantees table-or-nil carry a `-- @secret-safe:`
-- annotation instead. `X or Y` yields either side. NOT used for
-- truthiness/condition checks — those keep isTaintedRef.

-- Can this sub-expression's FALSY value carry taint? (`X and Y` yields
-- falsy(X); falsy(A and B) is falsy(A) or falsy(B); falsy(A or B) is
-- falsy(B).)
local function falsyYieldTainted(expr, taintSet, fieldTaintSet, registry)
    expr = stripParens(expr)
    if type(expr) ~= "table" then return false end
    if expr.AstType == "VarExpr" or expr.AstType == "MemberExpr"
        or expr.AstType == "IndexExpr" then
        return isTaintedRef(expr, taintSet, fieldTaintSet, registry)
    end
    if expr.AstType == "BinopExpr" then
        if expr.Op == "and" then
            return falsyYieldTainted(expr.Lhs, taintSet, fieldTaintSet, registry)
                or falsyYieldTainted(expr.Rhs, taintSet, fieldTaintSet, registry)
        end
        if expr.Op == "or" then
            return falsyYieldTainted(expr.Rhs, taintSet, fieldTaintSet, registry)
        end
    end
    return false
end

local function isValueTainted(expr, taintSet, fieldTaintSet, registry)
    expr = stripParens(expr)
    if isTaintedRef(expr, taintSet, fieldTaintSet, registry) then return true end
    if type(expr) == "table" and expr.AstType == "BinopExpr" then
        if expr.Op == "and" then
            return isValueTainted(expr.Rhs, taintSet, fieldTaintSet, registry)
                or falsyYieldTainted(expr.Lhs, taintSet, fieldTaintSet, registry)
        end
        if expr.Op == "or" then
            return isValueTainted(expr.Lhs, taintSet, fieldTaintSet, registry)
                or isValueTainted(expr.Rhs, taintSet, fieldTaintSet, registry)
        end
    end
    -- A constructor produces a plain table reference.  Secret values stored
    -- in its entries taint those entries, not the container reference or its
    -- unrelated fields; assignment handling records the entry keys in
    -- fieldTaintSet.
    return false
end

local function copySet(set)
    local copy = {}
    for k, v in pairs(set or {}) do
        if v then copy[k] = true end
    end
    return copy
end

local function clearParamTaint(taintSet, fieldTaintSet, funcNode)
    local function clearName(name)
        taintSet[name] = nil
        local prefix = name .. "."
        for key in pairs(fieldTaintSet) do
            if key:sub(1, #prefix) == prefix then
                fieldTaintSet[key] = nil
            end
        end
    end
    for _, arg in ipairs(funcNode.Arguments or {}) do
        if arg.Name then clearName(arg.Name) end
    end
    -- Colon declarations bind an implicit `self` parameter that the parser
    -- does not list in Arguments (round-8r, same quirk as the freshness
    -- shadow fix): the body's self is the RECEIVER, never the outer
    -- variable named self — its inherited taint must clear like any other
    -- parameter's.
    if type(funcNode.Name) == "table"
        and funcNode.Name.AstType == "MemberExpr"
        and funcNode.Name.Indexer == ":" then
        clearName("self")
    end
end

-- Unquoted value of a StringExpr node, or nil.
local function stringLiteralValue(n)
    if type(n) ~= "table" or n.AstType ~= "StringExpr" then return nil end
    local raw = n.Value and n.Value.Data
    if type(raw) ~= "string" then return nil end
    return raw:match("^[\"'](.*)[\"']$") or raw
end

-- Secret event payload detection (config event_payload_params): a function
-- whose body compares something against a secret-payload event-name literal
-- (`event == "UNIT_AURA"`) is treated as that event's handler, and the
-- configured payload parameter positions become taint sources. Positional by
-- necessity — the api-index metadata is per-event, not per-argument — and
-- keyed to the SetScript OnEvent signature (self, event, payload...); a
-- dispatch helper with a shifted signature needs its own config entry.
-- Handlers that never compare the event name are additionally detected via
-- the file-level RegisterEvent/SetScript linkage (collectRegisteredHandlers
-- below). Payload forwarded into helper functions (`Handle(unit, info)`)
-- stays unmodeled — the analyzer is non-interprocedural by design; helpers
-- need their own config entry or an annotation.
local function secretEventParamHits(funcNode, registry)
    if not registry.hasSecretPayloadEvents or not registry:hasSecretPayloadEvents() then
        return nil
    end
    local hits
    local events
    -- Gate governance (see Registry:payloadGateGoverned): if ANY matched
    -- event's payload is always-secret rather than restriction-conditional
    -- (UNIT_AURA_BLOCKED), the handler's payload class as a whole must not
    -- be blessed by aura-gate clears/proofs — AND across matched events.
    local governed = true
    local function walk(n, visited)
        if type(n) ~= "table" or visited[n] then return end
        visited[n] = true
        if n.AstType == "Function" then return end -- nested closure = own handler scope
        if n.AstType == "BinopExpr" and (n.Op == "==" or n.Op == "~=") then
            local lit = stringLiteralValue(n.Lhs) or stringLiteralValue(n.Rhs)
            local params = lit and registry:secretPayloadParams(lit)
            if params then
                hits = hits or {}
                events = events or {}
                events[lit] = params
                for _, pos in ipairs(params) do hits[pos] = true end
                if registry.payloadGateGoverned
                    and not registry:payloadGateGoverned(lit) then
                    governed = false
                end
            end
        end
        for k, v in pairs(n) do
            if k ~= "Tokens" and type(v) == "table" then walk(v, visited) end
        end
    end
    walk(funcNode.Body, {})
    return hits, governed, events
end

-- Per-analyze() module state (the walkers have fixed signatures and the walk
-- is single-threaded/synchronous; both are set in M.analyze / walkFunctionBody
-- and restored on exit):
--   registeredHandlerHits: Function AST node → { positions = {paramPos:
--     true}, events = {eventName:params}, gateGoverned = bool } for handlers
--     linked to secret events via RegisterEvent (no comparison needed).
--   fnEventCtx: the INNERMOST enclosing detected handler's context —
--     { eventName, payloadNames = {name:true}, payloadEvents,
--       varargSecret = {relPos:true}, independentFields = {key:true},
--       aliasCanon = {name:canonName} } —
--     consumed by the event-dispatch branch untaint, the vararg spill rule,
--     and the round-8 gate-scope provenance rules.
-- (Both locals are DECLARED near the top of the file so the low-level
-- helpers — canonFieldBase, isTaintedRef — can see them lexically.)

-- File-level RegisterEvent/SetScript linkage (round-6: handlers that never
-- compare the event name — single-event frames — were undetected): a receiver
-- that registers a secret-payload event AND assigns an OnEvent handler marks
-- that handler function's configured payload positions as taint sources.
-- Receiver identity is the parser's scope-resolved Variable OBJECT plus a
-- REBIND GENERATION (round-6b: bare-name union seeded unrelated same-named
-- frames across scopes, and a re-bound `f = CreateFrame(...)` inherited the
-- old frame's registrations — both reproducible false positives). The
-- statement-ordered walk bumps a variable's generation at every binding, so
-- registrations before a rebind never pair with handlers set after it.
-- Stable dotted receivers participate too. Handlers resolve from inline
-- closures, scoped value aliases, member storage, and simple factories that
-- directly return one closure; branch paths prevent sibling-arm cross-links.
local function collectRegisteredHandlers(ast, registry)
    if not registry.hasSecretPayloadEvents or not registry:hasSecretPayloadEvents() then
        return nil
    end
    -- recvKey → event records.  Each record carries its mutually-exclusive
    -- branch path so a RegisterEvent in one arm cannot link to a SetScript in
    -- a sibling arm that never executes in the same run.
    local recvEvents = {}
    -- recvKey → { primaries = handler records, hooks = handler records }.
    local recvHandlers = {}
    -- Scope-resolved variable identity → the function value currently held
    -- by that binding.  This models `local H = OnEvent; SetScript(..., H)`
    -- without letting a later rebind retroactively change the installed value.
    local handlerBindings = {}
    local memberHandlerBindings = {}
    local function returnedHandler(factory)
        local found, ambiguous
        local function walk(n)
            if type(n) ~= "table" or ambiguous then return end
            if n ~= factory and n.AstType == "Function" then return end
            if n.AstType == "ReturnStatement" then
                local args = n.Arguments or {}
                local value = #args == 1 and args[1] or nil
                if type(value) == "table" and value.AstType == "Function" then
                    if found and found ~= value then ambiguous = true else found = value end
                else
                    ambiguous = true
                end
                return
            end
            for k, v in pairs(n) do
                if k ~= "Tokens" and k ~= "Scope" and k ~= "Variable"
                    and type(v) == "table" then walk(v) end
            end
        end
        walk(factory.Body)
        return not ambiguous and found or nil
    end
    local gen = {}          -- Variable object / global-name key → rebind generation
    local function copyPath(path)
        local r = {}
        for node, arm in pairs(path or {}) do r[node] = arm end
        return r
    end
    local function pathsCompatible(a, b)
        for node, arm in pairs(a or {}) do
            if b and b[node] and b[node] ~= arm then return false end
        end
        return true
    end
    local function pathsEqual(a, b)
        for node, arm in pairs(a or {}) do if not b or b[node] ~= arm then return false end end
        for node, arm in pairs(b or {}) do if not a or a[node] ~= arm then return false end end
        return true
    end
    local function useId(n)
        if type(n) ~= "table" or n.AstType ~= "VarExpr" then return nil end
        return n.Variable or ("g:" .. tostring(n.Name))
    end
    local function resolveHandler(n)
        if type(n) ~= "table" then return nil end
        if n.AstType == "Function" then return n end
        if n.AstType == "Parentheses" then return resolveHandler(n.Inner) end
        if n.AstType == "VarExpr" then
            local v = handlerBindings[useId(n)]
            return type(v) == "table" and v.AstType == "Function" and v or nil
        end
        if n.AstType == "MemberExpr" then
            local path = callTargetName(n)
            path = path and path:gsub(":", ".")
            local v = path and memberHandlerBindings[path]
            return type(v) == "table" and v.AstType == "Function" and v or nil
        end
        if n.AstType == "CallExpr" then
            local factory = resolveHandler(n.Base)
            if factory then return returnedHandler(factory) end
        end
        return nil
    end
    local function recvIdentity(base)
        if type(base) ~= "table" then return nil end
        if base.AstType == "VarExpr" then
            local root = base.Variable or ("g:" .. tostring(base.Name))
            return tostring(root), root
        end
        if base.AstType == "MemberExpr" and base.Indexer == "."
            and base.Ident and base.Ident.Data then
            local prefix, root = recvIdentity(base.Base)
            if prefix then return prefix .. "." .. base.Ident.Data, root end
        end
        return nil
    end
    local function recvKeyOf(base)
        local raw, root = recvIdentity(base)
        if not raw then return nil end
        return raw .. "#r" .. (gen[root] or 0) .. "#p" .. (gen[raw] or 0)
    end
    -- Keys that leave the AST tree: Scope/Variable link INTO the parser's
    -- scope graph (parent chains reach the whole program) — recursing there
    -- with the per-statement `seen` tables below turns the walk quadratic
    -- and hangs on large files.
    local SKIP_KEYS = { Tokens = true, Scope = true, Variable = true }
    -- CallExprs in the CURRENT statement, outside nested closures/blocks
    -- (those walk in their own statement order via scanBlocks below).
    local function scanCalls(n, seen, path)
        if type(n) ~= "table" or seen[n] then return end
        seen[n] = true
        if n.AstType == "Function" or n.AstType == "Statlist" then return end
        if n.AstType == "CallExpr" then
            local name, kind = callTargetName(n.Base)
            if name and kind == "method"
                and n.Base and n.Base.AstType == "MemberExpr" then
                local method = getMethodNameFromQualified(name)
                local recv = recvKeyOf(n.Base.Base)
                if recv and (method == "RegisterEvent" or method == "RegisterUnitEvent") then
                    local lit = stringLiteralValue(n.Arguments and n.Arguments[1])
                    local params = lit and registry:secretPayloadParams(lit)
                    if params then
                        local list = recvEvents[recv] or {}
                        list[#list + 1] = {
                            eventName = lit,
                            params = params,
                            gateGoverned = not registry.payloadGateGoverned
                                or registry:payloadGateGoverned(lit),
                            path = copyPath(path),
                        }
                        recvEvents[recv] = list
                    end
                elseif recv and (method == "SetScript" or method == "HookScript") then
                    local lit = stringLiteralValue(n.Arguments and n.Arguments[1])
                    local handler = n.Arguments and n.Arguments[2]
                    if lit == "OnEvent" and type(handler) == "table" then
                        local rec = recvHandlers[recv]
                            or { primaries = {}, hooks = {} }
                        local fnNode = resolveHandler(handler)
                        if method == "SetScript" then
                            -- Exact same-path SetScript replaces the primary.
                            -- A narrower/alternate path remains as a possible
                            -- runtime primary on paths where the new call does
                            -- not execute.
                            local kept = {}
                            for _, old in ipairs(rec.primaries) do
                                if not pathsEqual(old.path, path) then
                                    kept[#kept + 1] = old
                                end
                            end
                            rec.primaries = kept
                            if fnNode then
                                rec.primaries[#rec.primaries + 1] = {
                                    fn = fnNode, path = copyPath(path) }
                            end
                        elseif fnNode then
                            rec.hooks[#rec.hooks + 1] = {
                                fn = fnNode, path = copyPath(path) }
                        end
                        recvHandlers[recv] = rec
                    end
                end
            end
        end
        for k, v in pairs(n) do
            if not SKIP_KEYS[k] and type(v) == "table" then scanCalls(v, seen, path) end
        end
    end
    local walkStmts
    -- Nested blocks and closure bodies re-enter the ordered statement walk.
    local function scanBlocks(n, seen, path)
        if type(n) ~= "table" or seen[n] then return end
        seen[n] = true
        if n.AstType == "Statlist" then
            walkStmts(n.Body, path)
            return
        end
        if n.AstType == "IfStatement" then
            for arm, clause in ipairs(n.Clauses or {}) do
                local armPath = copyPath(path)
                armPath[n] = arm
                walkStmts(clause.Body and clause.Body.Body, armPath)
            end
            return
        end
        if n.AstType == "Function" then
            if n.Name and n.Name.Name then
                local id = n.IsLocal and n.Name or useId(n.Name)
                if id then handlerBindings[id] = n end
            elseif n.Name and n.Name.AstType == "MemberExpr" then
                local memberPath = callTargetName(n.Name)
                if memberPath then
                    memberHandlerBindings[memberPath:gsub(":", ".")] = n
                end
            end
            walkStmts(n.Body and n.Body.Body, path)
            return
        end
        for k, v in pairs(n) do
            if not SKIP_KEYS[k] and type(v) == "table" then scanBlocks(v, seen, path) end
        end
    end
    walkStmts = function(stmts, path)
        if type(stmts) ~= "table" then return end
        -- Reachability (round-10d follow-up 7, Codex catch: dead loop-exit
        -- code contaminated the linkage): a RegisterEvent/SetScript after
        -- a flow-ending statement never executes — skip it, or a dead
        -- registration links a LIVE handler and its payload params become
        -- phantom taint sources.
        local unreachable = false
        for _, stmt in ipairs(stmts) do
            if not unreachable then
                scanCalls(stmt, {}, path)
                scanBlocks(stmt, {}, path)
                -- Bindings bump LAST: calls in this statement saw the
                -- receiver's pre-binding generation.
                if stmt.AstType == "LocalStatement" then
                    local resolved = {}
                    for i, rhs in ipairs(stmt.InitList or {}) do
                        resolved[i] = resolveHandler(rhs) or false
                    end
                    for i, v in ipairs(stmt.LocalList or {}) do
                        handlerBindings[v] = resolved[i] or false
                        gen[v] = (gen[v] or 0) + 1
                    end
                elseif stmt.AstType == "AssignmentStatement" then
                    local resolved = {}
                    for i, rhs in ipairs(stmt.Rhs or {}) do
                        resolved[i] = resolveHandler(rhs) or false
                    end
                    for i, l in ipairs(stmt.Lhs or {}) do
                        if type(l) == "table" and l.AstType == "VarExpr" then
                            local id = l.Variable or ("g:" .. tostring(l.Name))
                            handlerBindings[id] = resolved[i] or false
                            gen[id] = (gen[id] or 0) + 1
                        elseif type(l) == "table" and l.AstType == "MemberExpr" then
                            local memberPath = callTargetName(l)
                            if memberPath then
                                memberHandlerBindings[memberPath:gsub(":", ".")] =
                                    resolved[i] or false
                            end
                            local raw = recvIdentity(l)
                            if raw then gen[raw] = (gen[raw] or 0) + 1 end
                        end
                    end
                end
                if stmt.AstType and stmtEndsFlow(stmt) then
                    unreachable = true
                end
            end
        end
    end
    walkStmts(ast.Body or {}, {})
    local hits
    for recv, eventRecords in pairs(recvEvents) do
        local rec = recvHandlers[recv]
        local live = {}
        for _, h in ipairs(rec and rec.primaries or {}) do live[#live + 1] = h end
        for _, h in ipairs(rec and rec.hooks or {}) do
            live[#live + 1] = h
        end
        for _, handlerRec in ipairs(live) do
            local fnNode = handlerRec.fn
            if fnNode then
                hits = hits or {}
                local h = hits[fnNode] or { positions = {}, gateGoverned = true }
                h.events = h.events or {}
                for _, eventRec in ipairs(eventRecords) do
                    if pathsCompatible(handlerRec.path, eventRec.path) then
                        for _, pos in ipairs(eventRec.params) do h.positions[pos] = true end
                        h.events[eventRec.eventName] = eventRec.params
                        if not eventRec.gateGoverned then h.gateGoverned = false end
                    end
                end
                if next(h.positions) then hits[fnNode] = h end
            end
        end
    end
    return hits
end

-- Invocation-local table detection (round-8i): a name is a FRESH table when
-- every binding in this function body assigns it a table constructor and the
-- name never escapes — never used as a whole value (call argument, bare-ref
-- copy, return value, constructor entry, comparison/condition operand) and
-- never a method-call receiver.  Field reads/writes (`tmp.f`, `tmp[k]`) are
-- the only sanctioned uses.  Fields of such tables die with the invocation,
-- so a TERMINATED branch's writes to them roll back with the locals instead
-- of joining the heap union (which would be a reachable-path FALSE POSITIVE
-- — no later invocation can see them either).  Anything ambiguous stays
-- heap (conservative, keep-the-taint direction).
local function collectFreshTables(bodyNode)
    -- Scope/Variable link INTO the parser's scope graph (parent chains reach
    -- the whole program) — recursing there hangs on large files (same skip
    -- as collectRegisteredHandlers).
    local SKIP_KEYS = { Tokens = true, Scope = true, Variable = true }
    -- Round-8j: freshness is SYNTACTIC, ORDER-AWARE, and restricted to
    -- top-of-function-body bindings.  The vendored parser's scope model
    -- collapses shadowed locals onto one Variable object (verified: an inner
    -- do-block `local tmp = {}` claims every later `tmp` use in the
    -- function), so scope-resolved identity cannot distinguish an
    -- invocation-local table from an outer/upvalue HEAP table of the same
    -- name — the shadowing FALSE NEGATIVE.  Instead, a name is fresh iff:
    --   * its FIRST appearance is a `local name = {}` constructor binding
    --     that is a DIRECT statement of this function body (a nested-block
    --     binding cannot be told apart from a shadow of an outer table);
    --   * every other appearance is a dot/bracket field access, in
    --     statement order (a use BEFORE the binding refers to the outer
    --     variable);
    --   * it is never rebound to a non-constructor and never escapes.
    -- Anything ambiguous stays heap (keep-the-taint direction).
    local status = {}  -- name → "fresh" | "bad"
    -- shadowed (closure walks only): names bound by the closure chain's own
    -- parameters / top-level locals — uses of them are NOT captures of the
    -- outer table (round-8m).
    local walk
    walk = function(n, seen, isTopStmt, inClosure, shadowed)
        if type(n) ~= "table" or seen[n] then return end
        seen[n] = true
        local t = n.AstType
        if t == "Statlist" and type(n.Body) == "table" then
            for _, stmt in ipairs(n.Body) do
                walk(stmt, seen, false, inClosure, shadowed)
            end
            return
        end
        if t == "Function" then
            -- Function STATEMENT names first (round-8n): `local function
            -- tmp` binds a NEW local — inside a closure it shadows like a
            -- closure top-level local; outside it means the name is a
            -- function now, never the fresh table.  A global `function
            -- tmp()` (re)binds an outer name (bad unless shadowed).  A
            -- dotted `function M.f()` is a field write on M — handled by
            -- the member walk.
            local fname
            if type(n.Name) == "table" then
                if n.IsLocal and n.Name.Name then
                    fname = n.Name.Name
                elseif n.Name.AstType == "VarExpr" then
                    fname = n.Name.Name
                elseif n.Name.AstType == "MemberExpr"
                    or n.Name.AstType == "IndexExpr" then
                    -- Method/field DECLARATION (`function M.f()`,
                    -- `function M:m()`): a field WRITE on the base — the
                    -- colon only binds `self` at CALL time, so unlike a
                    -- `M:m()` call site this is not a receiver escape
                    -- (round-8p).  Same use rules as any field access.
                    local nb = n.Name.Base
                    if type(nb) == "table" and nb.AstType == "VarExpr" then
                        if inClosure then
                            if not (shadowed and shadowed[nb.Name]) then
                                status[nb.Name] = "bad"
                            end
                        elseif status[nb.Name] ~= "fresh" then
                            status[nb.Name] = "bad"
                        end
                    else
                        walk(n.Name, seen, false, inClosure, shadowed)
                    end
                end
            end
            if fname then
                if n.IsLocal then
                    if inClosure then
                        -- Top-level closure-local function shadows; a
                        -- nested one neither shadows nor marks (later uses
                        -- stay capture-conservative).
                        if isTopStmt and shadowed then
                            shadowed[fname] = true
                        end
                    else
                        status[fname] = "bad"
                    end
                elseif not (inClosure and shadowed and shadowed[fname]) then
                    status[fname] = "bad"
                end
            end
            -- Closure body (round-8l): any use of an OUTER name inside a
            -- nested function is a CAPTURE — the closure can outlive the
            -- invocation (timers, stored handlers), so captured tables are
            -- never invocation-local, field-only uses included.  The
            -- closure's own parameters shadow the outer name for its whole
            -- body (round-8m), and its top-level locals shadow from their
            -- binding onward; uses of shadowed names are the closure's own
            -- variables, not captures.
            local shadow = {}
            if shadowed then
                for k in pairs(shadowed) do shadow[k] = true end
            end
            if fname and n.IsLocal then
                -- Self-recursion refers to the function itself.
                shadow[fname] = true
            end
            if type(n.Name) == "table" and n.Name.AstType == "MemberExpr"
                and n.Name.Indexer == ":" then
                -- Colon declaration: the body's `self` is the method's own
                -- IMPLICIT parameter (the parser does not add it to
                -- Arguments) — it must shadow, or a body use of `self`
                -- reads as a capture of an outer name `self` (round-8q).
                shadow.self = true
            end
            for _, arg in ipairs(n.Arguments or {}) do
                if type(arg) == "table" and arg.Name then
                    shadow[arg.Name] = true
                end
            end
            local b = n.Body
            if type(b) == "table" and type(b.Body) == "table" then
                for _, stmt in ipairs(b.Body) do
                    walk(stmt, seen, true, true, shadow)
                end
            end
            return
        end
        if t == "NumericForStatement" or t == "GenericForStatement" then
            -- Loop variables are bindings scoped to the loop body
            -- (round-8o).  In a closure they SHADOW for exactly the body
            -- walk (a scoped copy, no leak past the loop); at the outer
            -- level a loop var colliding with a tracked name makes that
            -- name ambiguous for this order-based scan — heap.
            local loopVars = {}
            if t == "NumericForStatement" then
                if type(n.Variable) == "table" and n.Variable.Name then
                    loopVars[n.Variable.Name] = true
                end
                walk(n.Start, seen, false, inClosure, shadowed)
                walk(n.End, seen, false, inClosure, shadowed)
                if n.Step then walk(n.Step, seen, false, inClosure, shadowed) end
            else
                for _, v in ipairs(n.VariableList or {}) do
                    if type(v) == "table" and v.Name then
                        loopVars[v.Name] = true
                    end
                end
                for _, g in ipairs(n.Generators or {}) do
                    walk(g, seen, false, inClosure, shadowed)
                end
            end
            if inClosure then
                local shadow = {}
                if shadowed then
                    for k in pairs(shadowed) do shadow[k] = true end
                end
                for k in pairs(loopVars) do shadow[k] = true end
                walk(n.Body, seen, false, true, shadow)
            else
                for k in pairs(loopVars) do
                    if status[k] then status[k] = "bad" end
                end
                walk(n.Body, seen, false, false, shadowed)
            end
            return
        end
        if t == "LocalStatement" then
            local inits = n.InitList or {}
            -- Inits evaluate BEFORE the binding and may use the OUTER
            -- variable of the same name.
            for _, init in ipairs(inits) do
                walk(init, seen, false, inClosure, shadowed)
            end
            for i, v in ipairs(n.LocalList or {}) do
                local name = v.Name
                if name then
                    if inClosure then
                        -- A closure's own top-level local shadows the outer
                        -- name for the rest of the closure body.  Nested-
                        -- block locals do NOT (their extent is unknown to
                        -- this walk) — later uses stay capture-conservative.
                        if isTopStmt and shadowed then
                            shadowed[name] = true
                        end
                    else
                        local init = inits[i] and stripParens(inits[i])
                        local isCtor = type(init) == "table"
                            and init.AstType == "ConstructorExpr"
                        if isTopStmt and isCtor and status[name] == nil then
                            status[name] = "fresh"
                        else
                            status[name] = "bad"
                        end
                    end
                end
            end
            return
        end
        if t == "AssignmentStatement" then
            local rhs = n.Rhs or {}
            for _, r in ipairs(rhs) do
                walk(r, seen, false, inClosure, shadowed)
            end
            for i, l in ipairs(n.Lhs or {}) do
                if type(l) == "table" and l.AstType == "VarExpr" and l.Name then
                    if inClosure then
                        if not (shadowed and shadowed[l.Name]) then
                            status[l.Name] = "bad"
                        end
                    else
                        local init = rhs[i] and stripParens(rhs[i])
                        local isCtor = type(init) == "table"
                            and init.AstType == "ConstructorExpr"
                        -- A constructor REBIND of an already-fresh name
                        -- keeps it fresh (still invocation-local); anything
                        -- else is bad.
                        if not (isCtor and status[l.Name] == "fresh") then
                            status[l.Name] = "bad"
                        end
                    end
                else
                    walk(l, seen, false, inClosure, shadowed)
                end
            end
            return
        end
        if t == "MemberExpr" or t == "IndexExpr" then
            local base = n.Base
            if type(base) == "table" and base.AstType == "VarExpr" then
                if inClosure then
                    -- Capture unless shadowed by the closure's own params /
                    -- top-level locals (round-8m).
                    if not (shadowed and shadowed[base.Name]) then
                        status[base.Name] = "bad"
                    end
                elseif t == "MemberExpr" and n.Indexer == ":" then
                    -- Method receiver: the table escapes as `self`.
                    status[base.Name] = "bad"
                elseif status[base.Name] ~= "fresh" then
                    -- Field use before (or without) the fresh binding: the
                    -- name refers to an outer/heap table here.
                    status[base.Name] = "bad"
                end
            else
                walk(base, seen, false, inClosure, shadowed)
            end
            if t == "IndexExpr" then
                walk(n.Index, seen, false, inClosure, shadowed)
            end
            return
        end
        if t == "VarExpr" then
            -- Bare whole-value use in any other position: escape/ambiguous
            -- (shadowed closure-own names excepted — they are not the outer
            -- table).
            if not (inClosure and shadowed and shadowed[n.Name]) then
                status[n.Name] = "bad"
            end
            return
        end
        for k, v in pairs(n) do
            if not SKIP_KEYS[k] and type(v) == "table" then
                walk(v, seen, false, inClosure, shadowed)
            end
        end
    end
    local body = type(bodyNode) == "table" and bodyNode.Body
    if type(body) == "table" then
        local seen = {}
        for _, stmt in ipairs(body) do
            walk(stmt, seen, true, false, nil)
        end
    end
    local fresh = {}
    for name, st in pairs(status) do
        if st == "fresh" then fresh[name] = true end
    end
    return fresh
end

-- Names bound as params/locals anywhere in THIS function (nested closures
-- excluded — they re-scan under their own walkFunctionBody). Consumed by
-- the persistent-cache SEED gate: a seeded key whose root is bound locally
-- ANYWHERE in the function is skipped — the parser collapses shadowed
-- locals onto one Variable object (round-8j), so per-read scope resolution
-- is unavailable and seeding a shadowed name would flag the SHADOW's reads
-- (`local cache = {}` then `cache[1] or D` inside one function must not
-- inherit the chunk cache's seed). Union over all blocks: ambiguity only
-- UNDER-seeds (a missed cache-hit finding), never a FP. EXPORT decisions
-- do NOT use this union — see collectOuterVarNodes.
-- Colon declarations (`function obj:m()`) bind an implicit `self` the
-- parser omits from Arguments (same quirk walkFunctionBody's event-param
-- mapping compensates for) — every scope seeding below must add it or a
-- method body's `self` falls through to an enclosing binding of that name.
local function isColonFunction(fnNode)
    return type(fnNode.Name) == "table"
        and fnNode.Name.AstType == "MemberExpr"
        and fnNode.Name.Indexer == ":"
end

local function collectFnLocalNames(funcNode)
    local names = {}
    for _, arg in ipairs(funcNode.Arguments or {}) do
        if arg.Name then names[arg.Name] = true end
    end
    if isColonFunction(funcNode) then names.self = true end
    local SKIP_KEYS = { Tokens = true, Scope = true, Variable = true }
    local function walk(n, seen)
        if type(n) ~= "table" or seen[n] then return end
        seen[n] = true
        local t = n.AstType
        if t == "Function" then
            -- A `local function f` binds f in THIS scope before we skip
            -- the nested body.
            if n.IsLocal and type(n.Name) == "table" and n.Name.Name then
                names[n.Name.Name] = true
            end
            return
        end
        if t == "LocalStatement" then
            for _, v in ipairs(n.LocalList or {}) do
                if v.Name then names[v.Name] = true end
            end
        elseif t == "NumericForStatement" then
            if n.Variable and n.Variable.Name then
                names[n.Variable.Name] = true
            end
        elseif t == "GenericForStatement" then
            for _, v in ipairs(n.VariableList or {}) do
                if v.Name then names[v.Name] = true end
            end
        end
        for k, v in pairs(n) do
            if not SKIP_KEYS[k] and type(v) == "table" then
                walk(v, seen)
            end
        end
    end
    walk(funcNode.Body, {})
    return names
end

-- Block-aware lexical resolution for the persistent-cache EXPORT decision
-- (Codex round-10c catch: name-union suppression is lexically unsound —
-- an unrelated `do local cache = 5 end` shadow suppressed the export of a
-- genuine chunk-cache write later in the same function). Walks the
-- function body with a real scope STACK (block push/pop, Lua binding
-- order: LocalStatement inits are walked before their names bind;
-- repeat-until conditions see the body's locals; for-vars bind in the body
-- scope) and annotates every VarExpr USE that resolves to an OUTER binding
-- (upvalue/global — no enclosing local in scope at that point). Nested
-- Function bodies are skipped: they get their own map, and an enclosing
-- function's local IS persistent heap relative to the closure's calls.
local fnWalkInstance = 0
local function collectOuterVarNodes(funcNode)
    local outer = {}
    -- Freshness/value-escape land in the GLOBAL per-pass maps
    -- (fnBindingFresh / fnBindingValueEscaped) under qualified IDs, so
    -- privacy stays decidable after this walk ends (catch #10: inherited
    -- and captured evidence carries qualified IDs across walks).
    local escaped = fnBindingValueEscaped or {}
    local fresh = fnBindingFresh or {}
    fnWalkInstance = fnWalkInstance + 1
    local walkTag = "F" .. fnWalkInstance .. ":L"
    local nextId = 0
    local function newBindingId()
        nextId = nextId + 1
        return walkTag .. nextId
    end
    local scopes = { {} }
    for _, arg in ipairs(funcNode.Arguments or {}) do
        if arg.Name then
            local id = newBindingId()
            scopes[1][arg.Name] = id
            -- Declared-param binding annotation (round-23 helper-param
            -- seeding): the Argument NODE keys its own binding ID, the
            -- same way LocalStatement declaration targets are annotated
            -- below. Argument nodes are never read roots, so no other
            -- fnOuterVarNodes consumer can see these entries.
            outer[arg] = id
        end
    end
    if funcNode.VarArg then scopes[1]["..."] = newBindingId() end
    if isColonFunction(funcNode) then
        -- Implicit self is PRIVATE by default (unlike explicit params):
        -- the binding is invisible in source, so inheriting name-keyed
        -- heap evidence for an enclosing `self` table through it is pure
        -- name-collision noise (Codex catch #8b: a colon method body's
        -- `self[1] or DEFAULT` inherited an unrelated chunk-local self's
        -- seed). A bare `self` use (escape) still cancels the privacy.
        local id = newBindingId()
        scopes[1].self = id
        fresh[id] = true
    end
    -- Innermost binding ID for the name, or "outer" when nothing local
    -- binds it here.
    local function resolveBinding(name)
        for i = #scopes, 1, -1 do
            local id = scopes[i][name]
            if id then return id end
        end
        return "outer"
    end
    -- Nested-closure boundary (Codex catches #5/#6): closure bodies are
    -- walked WITH the parent scope stack. Scopes at or below the boundary
    -- index belong to the enclosing function — a use resolving there is a
    -- CAPTURE, and capture = escape (round-8l): the closure can read/write
    -- that table beyond this walk's flow-sensitivity. Closure-own
    -- params/locals shadow lexically, so a closure whose own `cache`
    -- binding is all it uses escapes nothing (#6's shadow-only FP).
    local closureBoundary = nil
    -- Parallel to `scopes`: does that block ALWAYS execute when its
    -- parent does? Function/do bodies do; if-clauses and loop bodies may
    -- run zero times (Codex catch #14: a rebind reached only through
    -- always-blocks dominates and may split identity). A repeat body runs
    -- at least once; a `break` can bypass LATER statements only (Codex
    -- catches #15/#16) — so the repeat starts "always" and the walk flips
    -- it to "maybe" when it actually ENCOUNTERS a break addressing it
    -- (statement order: rebinds walked before the break keep dominance;
    -- rebinds after it lost it). loopStack tracks the innermost loop —
    -- entries are `true` for while/for (already "maybe") and
    -- { repeatScopeIdx = n } for repeat bodies.
    local scopeKind = { "always" }
    local loopStack = {}
    local function dominatesScope(fromIdx)
        for i = fromIdx + 1, #scopes do
            if scopeKind[i] ~= "always" then return false end
        end
        return true
    end
    -- Active per-if-clause rebind collector (all-arms merge-split):
    -- [name] = { idx = declaring scope index, fresh = rhs fresh-shaped }.
    -- rebindCollectorClosed: an arm-ESCAPING break was walked — the arm
    -- can exit before any LATER rebind, so subsequent records are ignored;
    -- records made BEFORE the break already ran on that path and stay
    -- valid (Codex catch #17). rebindCollectorLoopDepth = #loopStack at
    -- collector install: a break addressing a loop ENTERED WITHIN the arm
    -- (stack deeper than at install) exits only that nested loop and the
    -- arm continues — it must not close the collector (Codex catch #18).
    local rebindCollector, rebindCollectorDepth, rebindCollectorClosed
    local rebindCollectorLoopDepth
    -- SUSPENDED inside nested closures: their rebinds must not count as
    -- definite arm records (execution timing unknown), but ESCAPE marks
    -- still apply — a capture-escape holds from closure creation (Codex
    -- catch #22: nested-closure Register(cache) bypassed the arm merge).
    local rebindCollectorSuspended = false
    -- Minimum #loopStack observed at any break in the CURRENT clause
    -- context (Codex catch #19: a sticky boolean lost the depth when an
    -- inner if/else collector boundary was crossed). Propagated outward on
    -- if restore and re-evaluated against each collector's install depth;
    -- pruned when leaving the loop it addressed.
    local rebindBreakMinDepth
    local function copyDirtyKeys(src)
        local out = {}
        for key in pairs(src or {}) do out[key] = true end
        return out
    end
    local function cloneCollector(src)
        local out = {}
        for name, rec in pairs(src or {}) do
            out[name] = {
                idx = rec.idx,
                fresh = rec.fresh,
                escaped = rec.escaped,
                binding = rec.binding,
                dirty = copyDirtyKeys(rec.dirty),
                -- `rebound` is relative to THIS if.  An inherited record
                -- carries activity state but does not mean that this if
                -- replaced the binding in every arm.
                rebound = false,
            }
        end
        return out
    end
    local function unionDirtyKeys(into, src)
        for key in pairs(src or {}) do into[key] = true end
    end
    local function definitelyCleanExpr(n)
        while type(n) == "table" and n.AstType == "Parentheses" do
            n = n.Inner
        end
        if type(n) ~= "table" then return false end
        local t = n.AstType
        if t == "NilExpr" or t == "NumberExpr" or t == "StringExpr"
            or t == "BooleanExpr" then
            return true
        end
        if t == "UnopExpr" then return definitelyCleanExpr(n.Rhs) end
        if t == "BinopExpr" then
            return definitelyCleanExpr(n.Lhs) and definitelyCleanExpr(n.Rhs)
        end
        if t == "ConstructorExpr" then
            for _, entry in ipairs(n.EntryList or {}) do
                if entry.Key and not definitelyCleanExpr(entry.Key) then
                    return false
                end
                if entry.Value and not definitelyCleanExpr(entry.Value) then
                    return false
                end
            end
            return true
        end
        return false
    end
    local function fieldWriteDirtyKey(lhs)
        local raw, volatile = chainRefKeyFwd(lhs)
        if raw and not volatile then return raw end
        local prefix = stableChainPrefix(lhs)
        if prefix then return prefix .. "[*]" end
        return nil
    end
    local function updateRecordForFieldWrite(rec, lhs, rhs)
        local key = fieldWriteDirtyKey(lhs)
        if not key then
            -- Unspellable writes can hit any descendant of this binding.
            local root = chainRootVarNode(lhs)
            if root and root.Name then key = root.Name .. "[*]" end
        end
        if not key then return end
        rec.dirty = rec.dirty or {}
        if definitelyCleanExpr(rhs) then
            rec.dirty[key] = nil
            -- A definitely-clean replacement also discards dirty
            -- descendants of that slot.
            local dot, bracket = key .. ".", key .. "["
            for old in pairs(rec.dirty) do
                if old:sub(1, #dot) == dot or old:sub(1, #bracket) == bracket then
                    rec.dirty[old] = nil
                end
            end
        else
            rec.dirty[key] = true
        end
    end
    local function noteUse(varNode, whole)
        local name = varNode.Name
        local idx, id
        for i = #scopes, 1, -1 do
            local b = scopes[i][name]
            if b then
                idx, id = i, b
                break
            end
        end
        if closureBoundary then
            -- Inside a nested closure: a mention resolving to an
            -- enclosing LOCAL binding is a CAPTURE — the node records the
            -- captured binding's qualified ID (catch #9: per-node lexical
            -- truth). Capture alone is NOT a value escape (catch #10):
            -- closure field writes flow by binding identity, so a
            -- captured-only fresh binding keeps its privacy. A BARE use
            -- inside the closure (call argument, copy, return, receiver)
            -- passes the VALUE onward — that escapes the binding exactly
            -- like a bare use in the owner itself.
            if id and idx <= closureBoundary and id ~= "outer" then
                if fnCapturedUpvalues then
                    fnCapturedUpvalues[varNode] = id
                end
                if whole then
                    escaped[id] = true
                    -- Collector stays visible through suspension for
                    -- escape marks (catch #22) — but only for THE SAME
                    -- binding the record describes: a captured same-named
                    -- block shadow is a different table (catch #23).
                    if rebindCollector and rebindCollector[name]
                        and rebindCollector[name].binding == id then
                        rebindCollector[name].escaped = true
                    end
                end
            end
            return
        end
        id = id or "outer"
        outer[varNode] = id
        if whole and id ~= "outer" then escaped[id] = true end
        -- A whole-value use of a COLLECTED name escapes the arm's rebind
        -- table too: the merge identity must not stay private (Codex
        -- catch #21 FN — Register(cache) in every arm).
        if whole and rebindCollector and rebindCollector[name]
            and rebindCollector[name].binding == id then
            rebindCollector[name].escaped = true
        end
    end
    local walkExprUses, walkStmt, walkBlock, walkClosure
    walkExprUses = function(n, seen)
        if type(n) ~= "table" or seen[n] then return end
        seen[n] = true
        local t = n.AstType
        if t == "Function" then
            walkClosure(n, seen)
            return
        end
        if t == "VarExpr" then
            -- Bare whole-value use (argument, copy, return, rebind).
            if n.Name then noteUse(n, true) end
            return
        end
        if t == "MemberExpr" or t == "IndexExpr" then
            -- Field-access chain: the ROOT VarExpr is not a whole-value
            -- use — annotate it without an escape — EXCEPT a method
            -- receiver (`t:m()`), which passes the table as self.
            local base, receiver = n, false
            while type(base) == "table"
                and (base.AstType == "MemberExpr" or base.AstType == "IndexExpr") do
                if base.AstType == "MemberExpr" and base.Indexer == ":" then
                    receiver = true
                end
                if base.AstType == "IndexExpr" and base.Index then
                    walkExprUses(base.Index, seen)
                end
                local nb = base.Base
                while type(nb) == "table" and nb.AstType == "Parentheses" do
                    nb = nb.Inner
                end
                base = nb
            end
            if type(base) == "table" and base.AstType == "VarExpr" then
                if base.Name then
                    seen[base] = true
                    noteUse(base, receiver)
                end
            else
                walkExprUses(base, seen)
            end
            return
        end
        for k, v in pairs(n) do
            if k ~= "Tokens" and k ~= "Scope" and k ~= "Variable"
                and type(v) == "table" then
                walkExprUses(v, seen)
            end
        end
    end
    -- One statement in the CURRENT innermost scope (LocalStatement binds
    -- into it; block-introducing statements open child scopes).
    walkStmt = function(stmt, seen)
        local t = stmt.AstType
        if t == "LocalStatement" then
            -- Inits evaluate BEFORE the names bind. Resolve same-name
            -- outer aliases FIRST: `local cache = cache` (the localize
            -- idiom) binds the SAME table the outer name holds — the new
            -- binding inherits the "outer" identity instead of a fresh ID,
            -- so seeds and outer-write provenance keep matching through it.
            local inits = stmt.InitList or {}
            local aliasBind = {}
            for i, v in ipairs(stmt.LocalList or {}) do
                local init = inits[i]
                while type(init) == "table" and init.AstType == "Parentheses" do
                    init = init.Inner
                end
                if v.Name and type(init) == "table"
                    and init.AstType == "VarExpr" and init.Name == v.Name then
                    -- Same-name localization (`local cache = cache`) is
                    -- an identity ALIAS: the new binding carries the
                    -- SOURCE binding — "outer", a same-function local, or
                    -- (via the cumulative capture map, Codex catch #11)
                    -- an enclosing function's qualified ID; mapping a
                    -- captured source to "outer" let the alias consume an
                    -- unrelated chunk seed. The init use is consumed by
                    -- the alias — record it WITHOUT the whole-value
                    -- escape (pure aliasing, both names stay tracked).
                    local rid = resolveBinding(v.Name)
                    if rid == "outer" and fnCapturedUpvalues
                        and fnCapturedUpvalues[init] then
                        rid = fnCapturedUpvalues[init]
                    end
                    aliasBind[v.Name] = rid
                    if not seen[init] then
                        seen[init] = true
                        noteUse(init, false)
                    end
                end
            end
            for _, init in ipairs(inits) do
                walkExprUses(init, seen)
            end
            for i, v in ipairs(stmt.LocalList or {}) do
                if v.Name then
                    if aliasBind[v.Name] then
                        scopes[#scopes][v.Name] = aliasBind[v.Name]
                    else
                        local id = newBindingId()
                        scopes[#scopes][v.Name] = id
                        local init = inits[i]
                        while type(init) == "table"
                            and init.AstType == "Parentheses" do
                            init = init.Inner
                        end
                        if type(init) == "table"
                            and (init.AstType == "ConstructorExpr"
                                or init.AstType == "NumberExpr"
                                or init.AstType == "StringExpr"
                                or init.AstType == "BooleanExpr"
                                or init.AstType == "NilExpr") then
                            fresh[id] = true
                        end
                    end
                    -- Local declaration nodes are also assignment targets
                    -- for constructor-field provenance.  They are not
                    -- VarExpr nodes, but the binding ID is equally precise.
                    outer[v] = scopes[#scopes][v.Name]
                end
            end
        elseif t == "Function" then
            -- `local function f` binds f here. A dotted/colon function
            -- statement is a field WRITE on its base — the colon binds
            -- self at CALL time only, so a declaration is NOT a receiver
            -- escape (round-8p; Codex catch #8: `function self:m()`
            -- falsely escaped the private binding while the dot form
            -- stayed clean). The body is walked behind the closure
            -- boundary so CAPTURES escape lexically (catches #5-#6).
            if stmt.IsLocal and type(stmt.Name) == "table" and stmt.Name.Name then
                scopes[#scopes][stmt.Name.Name] = newBindingId()
            elseif type(stmt.Name) == "table" then
                local nameBase = stmt.Name
                while type(nameBase) == "table"
                    and nameBase.AstType == "MemberExpr" do
                    nameBase = nameBase.Base
                end
                if type(nameBase) == "table"
                    and nameBase.AstType == "VarExpr" then
                    if nameBase.Name then
                        seen[nameBase] = true
                        noteUse(nameBase, false)
                    end
                else
                    walkExprUses(nameBase, seen)
                end
            end
            walkClosure(stmt, seen)
        elseif t == "IfStatement" then
            local clauses = stmt.Clauses or {}
            local hasElse = #clauses > 1 and clauses[#clauses].Condition == nil
            local prevCollector = rebindCollector
            local prevDepth = rebindCollectorDepth
            local prevClosed = rebindCollectorClosed
            local prevLoopDepth = rebindCollectorLoopDepth
            local prevBreakMin = rebindBreakMinDepth
            local prevSuspended = rebindCollectorSuspended
            -- An enclosing collector needs path-scoped ACTIVITY even for
            -- an else-less nested if: field writes/clean overwrites and
            -- escapes in one arm must be unioned with the fall-through
            -- state.  A top-level collector is still needed only for an
            -- all-arms (else-bearing) identity merge.
            local armRebinds = (hasElse or prevCollector ~= nil) and {} or nil
            local ifMin
            if armRebinds then rebindBreakMinDepth = nil end
            -- Merge dominance is judged at the IF'S ENTRY: an arm-local
            -- break downgrades the enclosing repeat for POST-if
            -- statements, but every counted arm rebinds before its own
            -- break, so the merge itself still dominates (#17).
            local preKinds
            if hasElse then
                preKinds = {}
                for i = 1, #scopes do preKinds[i] = scopeKind[i] end
            end
            for ci, clause in ipairs(clauses) do
                if clause.Condition then walkExprUses(clause.Condition, seen) end
                if armRebinds then
                    rebindCollector = cloneCollector(prevCollector)
                    rebindCollectorDepth = #scopes + 1
                    rebindCollectorClosed = false
                    rebindCollectorLoopDepth = #loopStack
                    -- A newly installed collector is live in ITS context,
                    -- even inside a closure.
                    rebindCollectorSuspended = false
                end
                walkBlock(clause.Body, seen, "maybe")
                if armRebinds then armRebinds[ci] = rebindCollector end
            end
            if armRebinds and not hasElse then
                -- Every condition may be false: preserve the collector's
                -- entry activity as an additional reachable exit.
                armRebinds[#clauses + 1] = cloneCollector(prevCollector)
            end
            if armRebinds then
                -- Propagate break DEPTH outward, not a sticky boolean
                -- (catch #19): the enclosing collector closes only when
                -- some clause's break addressed a loop at or below ITS
                -- install depth. An else-less if never replaces the
                -- collector, so its breaks acted on it directly.
                ifMin = rebindBreakMinDepth
                rebindCollector = prevCollector
                rebindCollectorDepth = prevDepth
                rebindCollectorLoopDepth = prevLoopDepth
                rebindCollectorClosed = prevClosed
                rebindCollectorSuspended = prevSuspended
                if prevBreakMin ~= nil
                    and (ifMin == nil or prevBreakMin < ifMin) then
                    rebindBreakMinDepth = prevBreakMin
                else
                    rebindBreakMinDepth = ifMin
                end
            end
            local definiteRebinds = {}
            stmt._quiEscapedDefiniteRebinds = nil
            stmt._quiDirtyDefiniteRebinds = nil
            if armRebinds and hasElse then
                -- Names DEFINITELY rebound by EVERY arm (else included):
                -- past the if, the old binding is unreachable — split to a
                -- fresh merge identity (Codex catch #14). Fresh only when
                -- every arm's rebind was fresh-shaped.
                for name, info in pairs(armRebinds[1]) do
                    local everywhere, allFresh = info.rebound == true, info.fresh
                    local anyEscaped = info.escaped or false
                    local mergedDirty = copyDirtyKeys(info.dirty)
                    for ci = 2, #clauses do
                        local rec = armRebinds[ci][name]
                        if not rec or not rec.rebound or rec.idx ~= info.idx then
                            everywhere = false
                            break
                        end
                        allFresh = allFresh and rec.fresh
                        anyEscaped = anyEscaped or rec.escaped or false
                        unionDirtyKeys(mergedDirty, rec.dirty)
                    end
                    if everywhere then
                        definiteRebinds[name] = true
                        if anyEscaped then
                            stmt._quiEscapedDefiniteRebinds =
                                stmt._quiEscapedDefiniteRebinds or {}
                            stmt._quiEscapedDefiniteRebinds[name] = true
                        end
                        if next(mergedDirty) ~= nil then
                            stmt._quiDirtyDefiniteRebinds =
                                stmt._quiDirtyDefiniteRebinds or {}
                            stmt._quiDirtyDefiniteRebinds[name] = mergedDirty
                        end
                        -- The merge itself is a rebind AT THE IF'S
                        -- POSITION: split only when that position
                        -- dominated the declaring scope AT IF ENTRY (an
                        -- if nested in a conditional block may never run —
                        -- catch #13; an arm-local break must not defeat
                        -- the merge — catch #17). The arms' conservative
                        -- walks already canceled the old binding's
                        -- privacy, which is the correct fallback.
                        local domAtEntry = true
                        for si = info.idx + 1, #scopes do
                            if preKinds[si] ~= "always" then
                                domAtEntry = false
                                break
                            end
                        end
                        if domAtEntry then
                            local nid = newBindingId()
                            scopes[info.idx][name] = nid
                            if allFresh and not anyEscaped then
                                fresh[nid] = true
                            end
                            if next(mergedDirty) ~= nil and fnBindingDirtyKeys then
                                fnBindingDirtyKeys[nid] = mergedDirty
                            end
                            -- An arm-escaped table IS the merged value on
                            -- that path: the merge identity inherits the
                            -- escape (Codex catch #21 FN).
                            if anyEscaped then escaped[nid] = true end
                        end
                        -- A definite rebind counts toward an enclosing
                        -- clause's collector too — recorded BEFORE the
                        -- ifMin closure below: every counted arm rebinds
                        -- before its own break, so the merged rebind
                        -- precedes any escape (Codex catch #20).
                        if rebindCollector and not rebindCollectorSuspended
                            and not rebindCollectorClosed
                            and dominatesScope(rebindCollectorDepth)
                            -- Only bindings declared BELOW the enclosing
                            -- clause survive it: a same-named SHADOW's
                            -- merge (declared inside the clause) must not
                            -- clobber the enclosing record (Codex catch
                            -- #24).
                            and info.idx < (rebindCollectorDepth or 0) then
                            rebindCollector[name] = {
                                idx = info.idx,
                                fresh = allFresh and not anyEscaped,
                                escaped = anyEscaped,
                                binding = scopes[info.idx][name],
                                dirty = mergedDirty,
                                rebound = true,
                            }
                        end
                    end
                end
            end
            if armRebinds and prevCollector then
                -- Nested branches that do NOT definitely replace a parent
                -- record still contribute activity to it.  Merge dirty
                -- fields by union (a secret on any reachable arm matters),
                -- freshness by intersection, and escapes by union.
                for name, parentRec in pairs(prevCollector) do
                    if not definiteRebinds[name] then
                        local allFresh, anyEscaped = true, false
                        local mergedDirty = {}
                        for _, arm in ipairs(armRebinds) do
                            local rec = arm[name] or parentRec
                            -- A same-named block shadow can legitimately
                            -- produce an inner collector record, but it is
                            -- not an exit state for the parent binding.
                            if rec.binding ~= parentRec.binding then
                                rec = parentRec
                            end
                            allFresh = allFresh and rec.fresh
                            anyEscaped = anyEscaped or rec.escaped or false
                            unionDirtyKeys(mergedDirty, rec.dirty)
                        end
                        parentRec.fresh = allFresh
                        parentRec.escaped = anyEscaped
                        parentRec.dirty = mergedDirty
                    end
                end
            end
            if armRebinds then
                -- NOW close the enclosing collector for statements after
                -- this if: an arm-escaping break bypasses them (catch
                -- #19), but never the merge recorded above.
                if ifMin ~= nil and rebindCollector
                    and ifMin <= (rebindCollectorLoopDepth or 0) then
                    rebindCollectorClosed = true
                end
            end
        elseif t == "WhileStatement" then
            if stmt.Condition then walkExprUses(stmt.Condition, seen) end
            loopStack[#loopStack + 1] = true
            walkBlock(stmt.Body, seen, "maybe")
            loopStack[#loopStack] = nil
            if rebindBreakMinDepth and rebindBreakMinDepth > #loopStack then
                rebindBreakMinDepth = nil
            end
        elseif t == "RepeatStatement" then
            -- until-clause sees the body's locals: keep the body scope open
            -- across the condition.
            local rbody = type(stmt.Body) == "table" and stmt.Body.Body
            scopes[#scopes + 1] = {}
            -- At-least-once; the BreakStatement branch downgrades this to
            -- "maybe" the moment an addressing break is walked (#15/#16).
            scopeKind[#scopes] = "always"
            loopStack[#loopStack + 1] = { repeatScopeIdx = #scopes }
            if type(rbody) == "table" then
                for _, inner in ipairs(rbody) do
                    walkStmt(inner, seen)
                end
            end
            if stmt.Condition then walkExprUses(stmt.Condition, seen) end
            loopStack[#loopStack] = nil
            if rebindBreakMinDepth and rebindBreakMinDepth > #loopStack then
                rebindBreakMinDepth = nil
            end
            scopes[#scopes] = nil
        elseif t == "NumericForStatement" then
            if stmt.Start then walkExprUses(stmt.Start, seen) end
            if stmt.End then walkExprUses(stmt.End, seen) end
            if stmt.Step then walkExprUses(stmt.Step, seen) end
            scopes[#scopes + 1] = {}
            scopeKind[#scopes] = "maybe"
            if stmt.Variable and stmt.Variable.Name then
                scopes[#scopes][stmt.Variable.Name] = newBindingId()
            end
            loopStack[#loopStack + 1] = true
            walkBlock(stmt.Body, seen, "maybe")
            loopStack[#loopStack] = nil
            if rebindBreakMinDepth and rebindBreakMinDepth > #loopStack then
                rebindBreakMinDepth = nil
            end
            scopes[#scopes] = nil
        elseif t == "GenericForStatement" then
            for _, g in ipairs(stmt.Generators or {}) do
                walkExprUses(g, seen)
            end
            scopes[#scopes + 1] = {}
            scopeKind[#scopes] = "maybe"
            for _, v in ipairs(stmt.VariableList or {}) do
                if v.Name then scopes[#scopes][v.Name] = newBindingId() end
            end
            loopStack[#loopStack + 1] = true
            walkBlock(stmt.Body, seen, "maybe")
            loopStack[#loopStack] = nil
            if rebindBreakMinDepth and rebindBreakMinDepth > #loopStack then
                rebindBreakMinDepth = nil
            end
            scopes[#scopes] = nil
        elseif t == "DoStatement" then
            walkBlock(stmt.Body, seen, "always")
        elseif t == "BreakStatement" then
            -- A break addressing a repeat means statements AFTER this
            -- point may be bypassed — downgrade that repeat's dominance
            -- (#16: rebinds already walked keep their split). An active
            -- if-arm collector also closes: later rebinds in this arm
            -- may be bypassed on the break path (#17).
            local top = loopStack[#loopStack]
            if type(top) == "table" then
                scopeKind[top.repeatScopeIdx] = "maybe"
            end
            if rebindCollector and not rebindCollectorSuspended
                and #loopStack <= (rebindCollectorLoopDepth or 0) then
                rebindCollectorClosed = true
            end
            if rebindBreakMinDepth == nil
                or #loopStack < rebindBreakMinDepth then
                rebindBreakMinDepth = #loopStack
            end
        elseif t == "AssignmentStatement" then
            -- RHS evaluates against the PRE-assignment bindings.
            for _, rhs in ipairs(stmt.Rhs or {}) do
                walkExprUses(rhs, seen)
            end
            for i, lhs in ipairs(stmt.Lhs or {}) do
                local l = lhs
                while type(l) == "table" and l.AstType == "Parentheses" do
                    l = l.Inner
                end
                local splitIdx
                if type(l) == "table" and l.AstType == "VarExpr" and l.Name then
                    for si = #scopes, 1, -1 do
                        if scopes[si][l.Name] then
                            splitIdx = si
                            break
                        end
                    end
                    if splitIdx and closureBoundary
                        and splitIdx <= closureBoundary then
                        -- Upvalue rebind: assigns the ANCESTOR's variable
                        -- from inside a closure — keep the conservative
                        -- whole-use escape model.
                        splitIdx = nil
                    end
                end
                if type(l) == "table"
                    and (l.AstType == "MemberExpr" or l.AstType == "IndexExpr")
                    and rebindCollector then
                    -- Suspended context (inside a closure): only writes
                    -- through CAPTURED roots reach the enclosing arm's
                    -- table; closure-own same-named locals do not.
                    -- Field activity does not make a fresh table alias an
                    -- unrelated replaced table.  Track the exact dirty key
                    -- on the collector record instead; the merged binding
                    -- admits evidence only for those keys.  Definitely-clean
                    -- overwrites clear that key path-locally.
                    local wroot = l
                    while type(wroot) == "table"
                        and (wroot.AstType == "MemberExpr"
                            or wroot.AstType == "IndexExpr") do
                        wroot = wroot.Base
                        while type(wroot) == "table"
                            and wroot.AstType == "Parentheses" do
                            wroot = wroot.Inner
                        end
                    end
                    if type(wroot) == "table" and wroot.AstType == "VarExpr"
                        and wroot.Name and rebindCollector[wroot.Name] then
                        -- Resolve the root's binding NOW (the capture map
                        -- populates later in this statement) and require
                        -- it to MATCH the record's — a same-named block
                        -- shadow is a different table (catch #23).
                        local rootIdx, rootId
                        for si = #scopes, 1, -1 do
                            if scopes[si][wroot.Name] then
                                rootIdx = si
                                rootId = scopes[si][wroot.Name]
                                break
                            end
                        end
                        local rootIsCapture = rootIdx ~= nil
                            and closureBoundary ~= nil
                            and rootIdx <= closureBoundary
                        if rootId ~= nil
                            and rebindCollector[wroot.Name].binding == rootId
                            and (not rebindCollectorSuspended or rootIsCapture) then
                            updateRecordForFieldWrite(
                                rebindCollector[wroot.Name], l,
                                (stmt.Rhs or {})[i])
                        end
                    end
                end
                if splitIdx and dominatesScope(splitIdx) then
                    -- Bare-name LOCAL rebind in the binding's DECLARING
                    -- block: statements there run sequentially, so the
                    -- assignment dominates everything after it — the NAME
                    -- moves to a FRESH binding identity from here on
                    -- (Codex catch #12: an alias binding kept the
                    -- ancestor's qualified ID across `cache = {}`, so a
                    -- captured write to the OLD table tainted the new
                    -- one). The old binding's own state is untouched: the
                    -- table it named did not change hands.
                    seen[l] = true
                    local nid = newBindingId()
                    scopes[splitIdx][l.Name] = nid
                    outer[l] = nid
                    local rhs = (stmt.Rhs or {})[i]
                    while type(rhs) == "table"
                        and rhs.AstType == "Parentheses" do
                        rhs = rhs.Inner
                    end
                    if type(rhs) == "table"
                        and (rhs.AstType == "ConstructorExpr"
                            or rhs.AstType == "NumberExpr"
                            or rhs.AstType == "StringExpr"
                            or rhs.AstType == "BooleanExpr"
                            or rhs.AstType == "NilExpr") then
                        fresh[nid] = true
                    end
                elseif splitIdx then
                    -- CONDITIONAL/LOOPED rebind (some block between the
                    -- declaring one and here may run zero times): identity
                    -- stays SHARED and the binding conservatively loses
                    -- privacy and freshness — taint recorded on the
                    -- not-taken path must survive (Codex catch #13).
                    seen[l] = true
                    local oldId = scopes[splitIdx][l.Name]
                    outer[l] = oldId
                    if oldId ~= "outer" then
                        escaped[oldId] = true
                        fresh[oldId] = nil
                    end
                    -- A rebind AFTER the arm's escaping break is not
                    -- recorded (bypassed on the break path), but it DOES
                    -- change the fall-through exit: the earlier record's
                    -- freshness no longer holds on every path (catch #20
                    -- follow-up).
                    if rebindCollector and not rebindCollectorSuspended
                        and rebindCollectorClosed
                        and rebindCollector[l.Name]
                        and rebindCollector[l.Name].binding == oldId then
                        rebindCollector[l.Name].fresh = false
                    end
                    -- Report to an enclosing if-clause collector when this
                    -- rebind dominates the CLAUSE (all-arms merge-split,
                    -- catch #14) and no arm-local break precedes it (#17).
                    if rebindCollector and not rebindCollectorSuspended
                        and not rebindCollectorClosed
                        and dominatesScope(rebindCollectorDepth)
                        -- Same clause-lifetime guard as the merge
                        -- propagation (catch #24): a shadow declared
                        -- inside the clause dies with it.
                        and splitIdx < (rebindCollectorDepth or 0) then
                        local rhs = (stmt.Rhs or {})[i]
                        while type(rhs) == "table"
                            and rhs.AstType == "Parentheses" do
                            rhs = rhs.Inner
                        end
                        local freshShaped = type(rhs) == "table"
                            and (rhs.AstType == "ConstructorExpr"
                                or rhs.AstType == "NumberExpr"
                                or rhs.AstType == "StringExpr"
                                or rhs.AstType == "BooleanExpr"
                                or rhs.AstType == "NilExpr")
                        rebindCollector[l.Name] = {
                            idx = splitIdx,
                            fresh = freshShaped or false,
                            binding = oldId,
                            dirty = {},
                            rebound = true,
                        }
                    end
                else
                    walkExprUses(l, seen)
                end
            end
        else
            -- Call, return, break: expression uses only.
            walkExprUses(stmt, seen)
        end
    end
    walkBlock = function(statlist, seen, kind)
        local body = type(statlist) == "table" and statlist.Body
        if type(body) ~= "table" then return end
        scopes[#scopes + 1] = {}
        scopeKind[#scopes] = kind or "always"
        for _, stmt in ipairs(body) do
            walkStmt(stmt, seen)
        end
        scopes[#scopes] = nil
    end
    -- Walk a nested closure's body behind the boundary: its params/locals
    -- shadow, uses resolving to enclosing scopes escape as captures. The
    -- outermost boundary wins for deeper nesting — anything resolving to a
    -- scope of THIS function is a capture no matter how deep.
    walkClosure = function(fnNode, seen)
        local prevBoundary = closureBoundary
        -- A closure's execution timing is unknown: suspend any active
        -- clause collector so its rebinds never count as definite.
        local prevClosed = rebindCollectorClosed
        local prevCollectorLoopDepth = rebindCollectorLoopDepth
        local prevBreakMin = rebindBreakMinDepth
        local prevSuspendedC = rebindCollectorSuspended
        -- Collector stays LIVE but suspended: escape marks apply, records
        -- do not (catch #22).
        rebindCollectorSuspended = true
        rebindBreakMinDepth = nil
        -- Breaks inside the closure address ITS loops, never an enclosing
        -- one.
        local prevLoopStack = loopStack
        loopStack = {}
        closureBoundary = closureBoundary or #scopes
        scopes[#scopes + 1] = {}
        scopeKind[#scopes] = "always"
        for _, a in ipairs(fnNode.Arguments or {}) do
            if a.Name then scopes[#scopes][a.Name] = newBindingId() end
        end
        if fnNode.VarArg then scopes[#scopes]["..."] = newBindingId() end
        -- Colon methods bind an implicit `self` the parser omits — without
        -- it a method body's `self` falsely captures (escapes) an
        -- enclosing local named self (Codex catch #7). Private by default
        -- like the top-level twin (catch #8b).
        if isColonFunction(fnNode) then
            local id = newBindingId()
            scopes[#scopes].self = id
            fresh[id] = true
        end
        walkBlock(fnNode.Body, seen, "always")
        scopes[#scopes] = nil
        closureBoundary = prevBoundary
        rebindCollectorClosed = prevClosed
        rebindCollectorLoopDepth = prevCollectorLoopDepth
        rebindBreakMinDepth = prevBreakMin
        rebindCollectorSuspended = prevSuspendedC
        loopStack = prevLoopStack
    end
    walkBlock(funcNode.Body, {})
    return outer
end

-- Export a tainted field-write key when it targets persistent heap state
-- from inside a function. The next fixpoint pass seeds these keys into
-- function bodies, modeling reads that hit a slot filled by an earlier
-- call or a sibling Fill function. Lexical soundness (Codex round-10c):
-- the decision is per-WRITE-SITE via collectOuterVarNodes — the LHS chain
-- root's VarExpr must resolve to an outer binding at that exact spot. An
-- alias-rewritten key (canonical root differs from the lexical root) has
-- no per-node resolution; it falls back to the conservative name union
-- (never exports a possibly-local root).
local function exportPersistentKey(key, lhsExpr)
    if not fnPersistentExports or not fnLocalNames or not key then return end
    local root = key:match("^([%a_][%w_]*)")
    if not root then return end
    local rootNode = lhsExpr and chainRootVarNode(lhsExpr)
    if rootNode and rootNode.Name == root then
        -- Persistent classes: true chunk/global writes export as "outer";
        -- CAPTURED-upvalue writes export the ancestor binding's qualified
        -- ID (catch #5's closure-fill flow matches the owner's reads by
        -- identity; catch #10's unrelated shadows never match). A write
        -- through the function's own direct local dies with the call —
        -- no export.
        if not fnOuterVarNodes then return end
        local id = fnOuterVarNodes[rootNode]
        if id ~= "outer" then return end
        local class = effectiveBindingId(id, rootNode)
        fnPersistentExports[key] = addProvClass(fnPersistentExports[key], class)
        return
    end
    if fnFreshTables and fnFreshTables[root] then return end
    if fnLocalNames[root] then return end
    fnPersistentExports[key] = addProvClass(fnPersistentExports[key], "outer")
end

-- Alias/chain identity is useful outside event handlers too (persistent
-- cache reads through `local alias = cache`).  Event payload metadata remains
-- optional; this base context carries only the general table-flow maps and
-- inherits aliases visible at a nested function's definition point.
local function newAliasFlowContext(parent)
    local ctx = {
        chainAlias = {}, independentFields = {},
        aliasCanon = {}, aliasPoisoned = {},
        mayAliasGeneration = parent and parent.mayAliasGeneration or 0,
        mayAliasQueryCache = {},
        mayAliasRelevantRoots = {},
        mayAliasCleanExact = {},
        mayAliasCleanSubtree = {},
        mayAliasCleanEdges = {},
        mayAliasEdgeVersions = {},
        mayAliasEdgeAllocator = parent and parent.mayAliasEdgeAllocator
            or { serial = 0 },
        invalidateMayAliasCache = invalidateMayAliasCache,
        markMayAliasConcreteClean = markMayAliasConcreteClean,
        refreshMayAliasEdge = refreshMayAliasEdge,
        bindingValueEscaped = fnBindingValueEscaped,
        functionSummaries = parent and parent.functionSummaries or nil,
        txnAllocator = parent and parent.txnAllocator or { serial = 0 },
    }
    for k, v in pairs(parent and parent.chainAlias or {}) do
        ctx.chainAlias[k] = v
    end
    for k, v in pairs(parent and parent.aliasCanon or {}) do
        ctx.aliasCanon[k] = v
    end
    for k in pairs(parent and parent.aliasPoisoned or {}) do
        ctx.aliasPoisoned[k] = true
    end
    -- May-alias links visible at definition time remain valid captures
    -- (round-10d). Per-slot sets are COPIED — a child's additions must
    -- not leak back into the parent's registry.
    if parent and parent.chainAliasMay then
        ctx.chainAliasMay = {}
        for slot, tgts in pairs(parent.chainAliasMay) do
            local set = {}
            for t in pairs(tgts) do set[t] = true end
            ctx.chainAliasMay[slot] = set
        end
    end
    for key in pairs(parent and parent.mayAliasCleanExact or {}) do
        ctx.mayAliasCleanExact[key] = true
    end
    for key in pairs(parent and parent.mayAliasCleanSubtree or {}) do
        ctx.mayAliasCleanSubtree[key] = true
    end
    for slot, targets in pairs(parent and parent.mayAliasEdgeVersions or {}) do
        local copy = {}
        for target, version in pairs(targets) do
            copy[target] = version
        end
        ctx.mayAliasEdgeVersions[slot] = copy
    end
    for key, cutoffs in pairs(parent and parent.mayAliasCleanEdges or {}) do
        local copy = {}
        for slot, targetCutoffs in pairs(cutoffs) do
            local targetCopy = {}
            for target, version in pairs(targetCutoffs) do
                targetCopy[target] = version
            end
            copy[slot] = targetCopy
        end
        ctx.mayAliasCleanEdges[key] = copy
    end
    return ctx
end

local function clearAliasFlowBinding(ctx, name)
    if not (ctx and name) then return end
    local function rooted(key)
        return key == name
            or key:sub(1, #name + 1) == name .. "."
            or key:sub(1, #name + 1) == name .. "["
    end
    if ctx.mayAliasRelevantRoots and ctx.mayAliasRelevantRoots[name] then
        invalidateMayAliasCache(ctx)
    end
    ctx.aliasCanon[name] = nil
    ctx.aliasPoisoned[name] = nil
    local dead = {}
    for slot in pairs(ctx.chainAlias or {}) do
        local plain = slot:sub(1, 1) == "~" and slot:sub(2) or slot
        if plain:match("^([%w_]+)") == name then dead[#dead + 1] = slot end
    end
    for _, slot in ipairs(dead) do ctx.chainAlias[slot] = nil end
    -- A parameter shadowing the name severs BOTH directions of any
    -- may-alias link: slots rooted at the name now spell a different
    -- table, and targets rooted at it would read the shadow's keys as if
    -- they were the captured table's (same key spelling, round-10d).
    if ctx.chainAliasMay then
        local deadMay = {}
        for slot, tgts in pairs(ctx.chainAliasMay) do
            if slot == name
                or slot:sub(1, #name + 1) == name .. "."
                or slot:sub(1, #name + 1) == name .. "[" then
                deadMay[#deadMay + 1] = slot
            else
                local deadTgts
                for t in pairs(tgts) do
                    if t == name
                        or t:sub(1, #name + 1) == name .. "."
                        or t:sub(1, #name + 1) == name .. "[" then
                        deadTgts = deadTgts or {}
                        deadTgts[#deadTgts + 1] = t
                    end
                end
                for _, t in ipairs(deadTgts or {}) do tgts[t] = nil end
                if next(tgts) == nil then
                    deadMay[#deadMay + 1] = slot
                end
            end
        end
        for _, slot in ipairs(deadMay) do ctx.chainAliasMay[slot] = nil end
    end
    for key in pairs(ctx.mayAliasCleanExact or {}) do
        if key == name or key:sub(1, #name + 1) == name .. "."
            or key:sub(1, #name + 1) == name .. "[" then
            ctx.mayAliasCleanExact[key] = nil
        end
    end
    for key in pairs(ctx.mayAliasCleanSubtree or {}) do
        if key == name or key:sub(1, #name + 1) == name .. "."
            or key:sub(1, #name + 1) == name .. "[" then
            ctx.mayAliasCleanSubtree[key] = nil
        end
    end
    -- Epoch metadata follows the structural edge lifecycle. Stale version
    -- rows are not consulted without a link, but pruning them prevents a
    -- later same-spelled binding from inheriting the old edge identity.
    for slot, versions in pairs(ctx.mayAliasEdgeVersions or {}) do
        local liveTargets = ctx.chainAliasMay
            and ctx.chainAliasMay[slot]
        if rooted(slot) or not liveTargets then
            ctx.mayAliasEdgeVersions[slot] = nil
        else
            for target in pairs(versions) do
                if rooted(target) or not liveTargets[target] then
                    versions[target] = nil
                end
            end
            if next(versions) == nil then
                ctx.mayAliasEdgeVersions[slot] = nil
            end
        end
    end
    for key, slots in pairs(ctx.mayAliasCleanEdges or {}) do
        if rooted(key) then
            ctx.mayAliasCleanEdges[key] = nil
        else
            for slot, targets in pairs(slots) do
                local liveTargets = ctx.chainAliasMay
                    and ctx.chainAliasMay[slot]
                if rooted(slot) or not liveTargets then
                    slots[slot] = nil
                else
                    for target in pairs(targets) do
                        if rooted(target) or not liveTargets[target] then
                            targets[target] = nil
                        end
                    end
                    if next(targets) == nil then slots[slot] = nil end
                end
            end
            if next(slots) == nil then ctx.mayAliasCleanEdges[key] = nil end
        end
    end
end

-- Helper-param seeding (round-23): a function STATEMENT whose DECLARED
-- name is registered via Registry:addElementContainerParams gets a
-- "<param>[*]" contamination marker seeded for each listed DECLARED
-- argument position. Marker only — the param name itself never enters
-- taintSet (the container reference stays truth-testable, `#`-able and
-- passable, exactly like a bind-site container), so only element reads
-- flag and the probed discipline scans clean. Positions index the
-- parser's Arguments list, which OMITS a colon declaration's implicit
-- `self` — position 1 of `function M:Copy(src)` is `src` (E22 pins it).
-- Name resolution covers the three statement shapes (`local function f`,
-- `function f`, `function M.f`/`M:f` — colon spellings normalize to the
-- dotted key); anonymous closures have no Name and never seed. Exact
-- spelling first; bare-tail fallback ONLY when the exact lookup missed
-- and the bare name itself is registered — a dotted registration never
-- answers for an unrelated declaration's tail. Provenance is the param's
-- OWN binding ID (the Argument-node annotation in collectOuterVarNodes),
-- so a fresh same-named shadow inside the body drops the evidence like
-- any param-rooted state. The marker is deliberately NEVER exported:
-- params are per-invocation locals, and exportPersistentKey refuses
-- param roots anyway (fnLocalNames covers every Argument name; a
-- param-rooted write resolves to a non-"outer" binding). Independent
-- provenance mirrors recordElementContainerMarker — a falsy restriction
-- gate does not prove elements readable.
local function seedElementContainerParams(funcNode, fieldTaintSet, registry)
    if not registry.elementContainerParams then return end
    local nameNode = funcNode.Name
    if type(nameNode) ~= "table" then return end
    local declName
    if funcNode.IsLocal then
        -- `local function f` — Name is the parser's scope-local record
        -- (no AstType); anonymous function EXPRESSIONS also carry
        -- IsLocal=true but have no Name table and bailed above.
        declName = nameNode.Name
    elseif nameNode.AstType == "VarExpr" then
        declName = nameNode.Name          -- `function f`
    elseif nameNode.AstType == "MemberExpr" then
        declName = callTargetName(nameNode)
        if declName then declName = declName:gsub(":", ".") end
    end
    if type(declName) ~= "string" then return end
    local positions = registry:elementContainerParams(declName)
    if not positions then
        local tail = declName:match("([%w_]+)$")
        if tail and tail ~= declName then
            positions = registry:elementContainerParams(tail)
        end
    end
    if type(positions) ~= "table" then return end
    for _, pos in ipairs(positions) do
        local arg = funcNode.Arguments and funcNode.Arguments[pos]
        local name = arg and arg.Name
        if name then
            local marker = name .. "[*]"
            fieldTaintSet[marker] = true
            if fnKeyProvenance and fnOuterVarNodes then
                local id = fnOuterVarNodes[arg]
                if id then fnKeyProvenance[marker] = id end
            end
            if fnEventCtx then
                fnEventCtx.independentFields =
                    fnEventCtx.independentFields or {}
                fnEventCtx.independentFields[marker] = true
            end
        end
    end
end

local function walkFunctionBody(funcNode, taintSet, fieldTaintSet, findings, registry, filePath, debug)
    if not (funcNode.Body and funcNode.Body.Body) then return end
    local prevFresh = fnFreshTables
    local prevSafeRefs = safeRefSet
    local prevLocalNames = fnLocalNames
    local prevOuterVarNodes = fnOuterVarNodes
    local prevProvenance = fnKeyProvenance
    -- A closure can run after the guard/path that created it; do not inherit
    -- field proofs from its definition point.
    safeRefSet = {}
    fnFreshTables = collectFreshTables(funcNode.Body)
    fnLocalNames = collectFnLocalNames(funcNode)
    fnOuterVarNodes = fnPersistentExports and collectOuterVarNodes(funcNode) or nil
    local closureTaint = copySet(taintSet)
    local closureFieldTaint = copySet(fieldTaintSet)
    -- Persistent cache slots (round-10b): keys some function fills with a
    -- tainted value survive across calls — every function body starts with
    -- them tainted so the cache-HIT read path (read-before-write, split
    -- Fill/Read) is modeled. A clean overwrite inside this body still
    -- clears the key flow-sensitively, and a guard bail still proves it.
    -- Per-read soundness (round-10c): seeding is UNCONDITIONAL; every
    -- recorded key carries BINDING provenance (fnKeyProvenance) — "outer"
    -- for seeds and inherited parent entries (every parent binding is
    -- outer from this closure's viewpoint), the write root's binding ID
    -- for real writes — and every fieldTaintSet consumer verifies hits
    -- against the read root's binding ID (bindingEvidenceUsable). Shadow
    -- reads name a different table and skip mismatched evidence; outer
    -- reads keep it; mixed functions resolve each read on its own.
    if fnOuterVarNodes then
        local prov = {}
        if prevProvenance then
            -- Inheritance copies entries AS-IS: qualified binding IDs are
            -- per-pass global, so ancestry identity survives any nesting
            -- depth (catch #10 — no class flattening).
            for k, v in pairs(prevProvenance) do prov[k] = v end
        end
        if fnPersistentSeed then
            -- Seeds carry their exporters' class sets ("outer" for chunk
            -- writes, qualified IDs for captured-upvalue writes). Union
            -- into the inherited entry — never clobber (#9 control).
            for k, classes in pairs(fnPersistentSeed) do
                closureFieldTaint[k] = true
                if type(classes) == "table" then
                    for c in pairs(classes) do
                        prov[k] = addProvClass(prov[k], c)
                    end
                else
                    prov[k] = addProvClass(prov[k], classes)
                end
            end
        end
        fnKeyProvenance = prov
    else
        fnKeyProvenance = nil
    end
    clearParamTaint(closureTaint, closureFieldTaint, funcNode)
    local eventParams, hitsGoverned, eventHits = secretEventParamHits(funcNode, registry)
    local regHits = registeredHandlerHits and registeredHandlerHits[funcNode]
    if regHits then
        eventParams = eventParams or {}
        for pos in pairs(regHits.positions) do eventParams[pos] = true end
        eventHits = eventHits or {}
        for eventName, params in pairs(regHits.events or {}) do
            eventHits[eventName] = params
        end
    end
    -- Gate governance ANDs across BOTH detection paths (comparison hits and
    -- RegisterEvent linkage): one always-secret event in the mix and the
    -- handler's payload class must not be blessed by aura-gate clears.
    local ctxGoverned = hitsGoverned ~= false
        and not (regHits and regHits.gateGoverned == false)
    local prevCtx = fnEventCtx
    local inheritedFlow = newAliasFlowContext(prevCtx)
    if eventParams then
        local nArgs = #(funcNode.Arguments or {})
        -- LuaMinify omits a colon declaration's implicit `self` from
        -- Arguments, while event_payload_params uses the runtime OnEvent
        -- signature `(self, event, ...)`.  Translate configured positions
        -- back into the parser's explicit-argument indices.
        local implicitSelf = type(funcNode.Name) == "table"
            and funcNode.Name.AstType == "MemberExpr"
            and funcNode.Name.Indexer == ":"
        local argOffset = implicitSelf and 1 or 0
        local payloadNames = {}
        local varargSecret
        local entryPayloadEvents = {}
        local eventVarargSecrets = {}
        for pos in pairs(eventParams) do
            local argIndex = pos - argOffset
            local arg = argIndex >= 1 and funcNode.Arguments
                and funcNode.Arguments[argIndex]
            local name = arg and arg.Name
            if name then
                closureTaint[name] = true
                payloadNames[name] = true
            elseif funcNode.VarArg and argIndex > nArgs then
                -- Configured position lands in `...`: remember its RELATIVE
                -- vararg index so a `local unit, info = ...` spill taints the
                -- right locals (see the DotsExpr rule in walkStatements).
                varargSecret = varargSecret or {}
                varargSecret[argIndex - nArgs] = true
            end
        end
        -- Preserve the event-to-position relation instead of only the union.
        -- Mixed handlers can then clear position 3 in an event whose secret
        -- payload is only position 4 (and vice versa).
        for eventName, params in pairs(eventHits or {}) do
            local eventVarargs
            for _, pos in ipairs(params) do
                local argIndex = pos - argOffset
                local arg = argIndex >= 1 and funcNode.Arguments
                    and funcNode.Arguments[argIndex]
                if arg and arg.Name then
                    local set = entryPayloadEvents[arg.Name] or {}
                    set[eventName] = true
                    entryPayloadEvents[arg.Name] = set
                elseif funcNode.VarArg and argIndex > nArgs then
                    eventVarargs = eventVarargs or {}
                    eventVarargs[argIndex - nArgs] = true
                end
            end
            eventVarargSecrets[eventName] = eventVarargs or {}
        end
        local eventArgIndex = 2 - argOffset
        local evArg = funcNode.Arguments and funcNode.Arguments[eventArgIndex]
        local payloadEvents = {}
        for name, events in pairs(entryPayloadEvents) do
            local copy = {}
            for eventName in pairs(events) do copy[eventName] = true end
            payloadEvents[name] = copy
        end
        fnEventCtx = {
            eventName = evArg and evArg.Name or nil,
            payloadNames = payloadNames,
            varargSecret = varargSecret,
            secretEvents = eventHits or {},
            entryPayloadEvents = entryPayloadEvents,
            payloadEvents = payloadEvents,
            eventVarargSecrets = eventVarargSecrets,
            -- false when any detected event's payload is ALWAYS secret
            -- (not restriction-conditional): aura-gate clears and the gate
            -- wildcard proof are inert for this handler.
            gateGoverned = ctxGoverned,
            -- slot-chain → canonical source ("updateInfo.sub" → "t2" after
            -- `updateInfo.sub = t2`): live key unification (round-9f).
            chainAlias = inheritedFlow.chainAlias,
            -- Merge-dropped may-alias links captured at definition time
            -- (round-10d) — inheritedFlow is fresh per closure, so this
            -- reuse cannot leak child additions to the parent.
            chainAliasMay = inheritedFlow.chainAliasMay,
            mayAliasGeneration = inheritedFlow.mayAliasGeneration,
            mayAliasQueryCache = {},
            mayAliasRelevantRoots = {},
            mayAliasCleanExact = inheritedFlow.mayAliasCleanExact,
            mayAliasCleanSubtree = inheritedFlow.mayAliasCleanSubtree,
            mayAliasCleanEdges = inheritedFlow.mayAliasCleanEdges,
            mayAliasEdgeVersions = inheritedFlow.mayAliasEdgeVersions,
            mayAliasEdgeAllocator = inheritedFlow.mayAliasEdgeAllocator,
            invalidateMayAliasCache =
                inheritedFlow.invalidateMayAliasCache,
            markMayAliasConcreteClean =
                inheritedFlow.markMayAliasConcreteClean,
            refreshMayAliasEdge =
                inheritedFlow.refreshMayAliasEdge,
            -- "<root>.<field>" keys whose taint is NOT payload-derived
            -- (assigned from an independent source onto a payload-named
            -- table) — excluded from gate clears/proofs (round-8b).
            independentFields = {},
            -- table-alias map for canonical field keys (round-8d) and the
            -- cross-path ambiguity marks that gate it (round-8e).
            aliasCanon = inheritedFlow.aliasCanon,
            aliasPoisoned = inheritedFlow.aliasPoisoned,
            bindingValueEscaped = inheritedFlow.bindingValueEscaped,
            functionSummaries = inheritedFlow.functionSummaries,
            txnAllocator = inheritedFlow.txnAllocator,
        }
    else
        -- Nested closures are their own payload-handler scope, but ordinary
        -- table aliases visible at definition time remain valid captures.
        fnEventCtx = inheritedFlow
    end
    -- Parameters (including implicit self) shadow any same-named alias from
    -- the enclosing flow context.
    for _, arg in ipairs(funcNode.Arguments or {}) do
        if arg.Name then clearAliasFlowBinding(fnEventCtx, arg.Name) end
    end
    if isColonFunction(funcNode) then clearAliasFlowBinding(fnEventCtx, "self") end
    -- Helper-param seeding (round-23): AFTER clearParamTaint above — the
    -- seed must survive the parameter clear — and after the flow-context
    -- swap so the independent-provenance mark lands on THIS body's ctx.
    seedElementContainerParams(funcNode, closureFieldTaint, registry)
    walkStatements(funcNode.Body.Body, closureTaint, closureFieldTaint, findings, registry, filePath, debug)
    fnEventCtx = prevCtx
    fnFreshTables = prevFresh
    safeRefSet = prevSafeRefs
    fnLocalNames = prevLocalNames
    fnOuterVarNodes = prevOuterVarNodes
    fnKeyProvenance = prevProvenance
end

-- pcall/xpcall used INSIDE an expression (condition, binop/unop operand,
-- builtin argument) truncates to its first return — the ok boolean — which is
-- always clean. Only multi-assignment (`local ok, v = pcall(src)`) spills the
-- protected function's possibly-secret returns; that flows through the
-- statement walkers, not these sites. Used to mask the source-contribution of
-- a DIRECT protected call so `if pcall(SecretSource, id) then` stays clean.
local function isProtectedCallExpr(expr)
    local inner = stripParens(expr)
    if type(inner) ~= "table" or inner.AstType ~= "CallExpr" then return false end
    local name = callTargetName(inner.Base)
    return name == "pcall" or name == "xpcall"
end

-- Position-precise taint for `select(k, ...)` inside a detected event
-- handler.  resultIndex is the selected call's return position (1 for scalar
-- use); nil asks whether ANY expanded return can be secret, as in the final
-- argument of `print(select(1, ...))`.  nil return means "not this shape";
-- false means this shape is proven clean.
local function selectVarargTaint(expr, resultIndex)
    local parenthesized = type(expr) == "table" and expr.AstType == "Parentheses"
    local call = stripParens(expr)
    if type(call) ~= "table" or call.AstType ~= "CallExpr"
        or callTargetName(call.Base) ~= "select" then
        return nil
    end
    local ctx = fnEventCtx
    if not (ctx and ctx.varargSecret and not ctx.suppressSpill) then return false end
    local args = call.Arguments or {}
    local kArg, dotsArg = args[1], args[2]
    if not (kArg and dotsArg and dotsArg.AstType == "DotsExpr") then return nil end
    if parenthesized and resultIndex and resultIndex > 1 then return false end
    if stringLiteralValue(kArg) == "#" then return false end
    if kArg.AstType == "NumberExpr" then
        local k = tonumber(kArg.Value and kArg.Value.Data)
        if not k or k == 0 then return false end
        -- Negative select indices depend on the runtime vararg count; retain
        -- taint conservatively when any configured payload slot is secret.
        if k < 0 then return next(ctx.varargSecret) ~= nil end
        if resultIndex then return ctx.varargSecret[k + resultIndex - 1] == true end
        for pos in pairs(ctx.varargSecret) do
            if pos >= k then return true end
        end
        return false
    end
    -- Dynamic clean indices may select any payload position.
    return true
end

-- Taint of a particular return from a multi-return RHS.  nil means the
-- shape has no special positional model and the caller may use its ordinary
-- conservative spill rule.
-- Second return (round-23 F5b) classifies PROVABLE spill values for the
-- member-write strong update — element knowledge lives here so
-- walkStatements (at Lua 5.1's 60-upvalue ceiling) reaches it through an
-- already-captured helper: "element" = the fresh container lands at this
-- index (clear-then-record-marker); "nil" = provably nil (truncating
-- parentheses, or past the single-container contract); "boolean" = the
-- pcall ok flag. nil kind = unknown content (conservative, no strong
-- update). Element shapes report taint FALSE, never nil: the container
-- reference itself is never secret (marker track), and the origin
-- fallback must not re-taint it.
local function multiReturnTaint(expr, resultIndex, registry)
    local selected = selectVarargTaint(expr, resultIndex)
    if selected ~= nil then return selected end
    if type(expr) == "table" and expr.AstType == "Parentheses"
        and resultIndex > 1 then
        -- parentheses truncate a call to one result: spill slots are nil
        return false, "nil"
    end
    local call = stripParens(expr)
    if type(call) ~= "table" or call.AstType ~= "CallExpr" then return nil end
    local name = callTargetName(call.Base)
    if name == "pcall" or name == "xpcall" then
        local fnArg = call.Arguments and call.Arguments[1]
        local fnName = fnArg and callTargetName(fnArg)
        if fnName and registry:isSource(fnName) then
            return resultIndex > 1 -- first result is the clean success boolean
        end
        if fnName and isElementSecretCallName(fnName, registry) then
            if resultIndex == 1 then return false, "boolean" end
            if resultIndex == 2 then return false, "element" end
            return false, "nil"
        end
    elseif name and registry:isSource(name) then
        return true
    elseif name and isElementSecretCallName(name, registry) then
        return false, resultIndex == 1 and "element" or "nil"
    end
    return nil
end

local function walkConditionExpr(expr, taintSet, fieldTaintSet, findings, registry, filePath)
    local inner = stripParens(expr)
    if isTaintedRef(inner, taintSet, fieldTaintSet, registry) then
        emit(findings, filePath, nodeLine(inner), 1, "<truthiness>",
            "<tainted-local>",
            "tainted value used as a branch condition without guard or C-side decode")
    end
    local hadSource = walkExpr(expr, taintSet, fieldTaintSet, findings, registry, filePath)
    -- Unsafe probe order (`x and issecretvalue(x)`, `not x or issecretvalue(x)`)
    -- scans the FULL condition once, with path context intact. Conditions
    -- truth-test the chain tail (topTested=true). Runs AFTER the sink walk so
    -- the deferred tainted-truth-test emission can defer to more specific
    -- same-line findings (see walkExprTop).
    detectUnsafeProbeOrder(expr, taintSet, fieldTaintSet, findings, registry, filePath, true)
    purgeMutableSafeRefs(expr, registry)
    -- Bare direct source-call condition (`if icon:IsShown() then`): the call
    -- result is truth-tested without ever landing in a local, so the
    -- tainted-ref check above can't see it. Only the bare-call shape emits
    -- here — compound conditions (and/or, comparisons, unary not) already
    -- emit inside walkExpr, and guard/gate calls are not sources.
    if hadSource and inner and inner.AstType == "CallExpr"
        and not isProtectedCallExpr(inner) then
        emit(findings, filePath, nodeLine(inner), 1, "<truthiness>",
            "<tainted-local>",
            "tainted value used as a branch condition without guard or C-side decode")
    end
    return hadSource
end

-- Inspect a condition expression. If it matches a guard pattern, return a
-- table { kind = "untaint-then" | "untaint-else", locals = { name1, ... } }.
-- Otherwise return nil.
-- Patterns matched:
--   not Guard(x)  → kind = "untaint-then"  (untaint x in the then-branch)
--   Guard(x)      → kind = "untaint-else"  (untaint x in the else-branch)
local function analyzeGuard(cond, registry)
    if type(cond) ~= "table" then return nil end

    local negated = false
    local inner = cond
    if cond.AstType == "UnopExpr" and cond.Op == "not" then
        negated = true
        inner = cond.Rhs
    end

    if inner and inner.AstType == "CallExpr" then
        local name = callTargetName(inner.Base)
        if name and isGuardName(name, registry) then
            local locals, refs = {}, {}
            if inner.Arguments then
                for _, a in ipairs(inner.Arguments) do
                    if isVarRef(a) then
                        locals[#locals + 1] = a.Name
                    elseif chainRefKeyFwd then
                        local rawKey = chainRefKeyFwd(a)
                        if rawKey then
                            refs[#refs + 1] = canonChainKeyFwd
                                and canonChainKeyFwd(rawKey) or rawKey
                        end
                    end
                end
            end
            if #locals == 0 and #refs == 0 then return nil end
            return {
                kind = negated and "untaint-then" or "untaint-else",
                locals = locals,
                refs = refs,
            }
        end
    end

    -- All-guard OR-chain (round-12): `Guard(x) or Guard(y) or Guard(z)` —
    -- the canonical multi-value probe bail (`if RSV(a) or RSV(b) then
    -- return nil end`). Condition FALSE means EVERY disjunct was false,
    -- i.e. every probed value proved non-secret — exactly untaint-else
    -- semantics (else/elseif/fall-through). The taken branch proves only
    -- "some disjunct true", so no untaint-then. ANY non-guard-call
    -- disjunct disqualifies the shape (a mixed chain's later disjuncts
    -- prove nothing about values the earlier guards didn't probe).
    if not negated and inner and inner.AstType == "BinopExpr" and inner.Op == "or" then
        local disjuncts = {}
        local function flattenOr(n)
            n = stripParens(n)
            if type(n) == "table" and n.AstType == "BinopExpr" and n.Op == "or" then
                flattenOr(n.Lhs)
                flattenOr(n.Rhs)
            else
                disjuncts[#disjuncts + 1] = n
            end
        end
        flattenOr(inner)
        local locals, refs = {}, {}
        for _, d in ipairs(disjuncts) do
            d = stripParens(d)
            local isGuardCall = false
            if type(d) == "table" and d.AstType == "CallExpr" then
                local gname = callTargetName(d.Base)
                if gname and isGuardName(gname, registry) then
                    isGuardCall = true
                    for _, a in ipairs(d.Arguments or {}) do
                        if isVarRef(a) then
                            locals[#locals + 1] = a.Name
                        elseif chainRefKeyFwd then
                            local rawKey = chainRefKeyFwd(a)
                            if rawKey then
                                refs[#refs + 1] = canonChainKeyFwd
                                    and canonChainKeyFwd(rawKey) or rawKey
                            end
                        end
                    end
                end
            end
            if not isGuardCall then return nil end
        end
        if #locals > 0 or #refs > 0 then
            return { kind = "untaint-else", locals = locals, refs = refs }
        end
        return nil
    end

    -- Probe idiom (round-6, tightened round-7): `issecretvalue and
    -- issecretvalue(x)` — the RIGHTMOST conjunct is the guard call; every
    -- leading conjunct must be a dotted prefix of the guard's own call chain
    -- (`Helpers`, `issecretvalue`), i.e. an existence check FOR THE GUARD.
    -- A leading conjunct that truth-tests the probed local itself
    -- (`x and issecretvalue(x)`) is NOT a guard — a secret x throws on that
    -- truth-test before the probe ever runs (live error: "attempt to perform
    -- boolean test on ..."), which is the exact defect the probe exists to
    -- prevent. That shape is rejected here and emits a probe-order finding
    -- via detectUnsafeProbeOrder in walkExpr's and/or handling. Any other
    -- extra conjunct disqualifies the shape too. Negated compound probes are
    -- not modeled.
    if not negated and inner and inner.AstType == "BinopExpr" and inner.Op == "and" then
        local conjuncts = {}
        local function flatten(n)
            n = stripParens(n)
            if type(n) == "table" and n.AstType == "BinopExpr" and n.Op == "and" then
                flatten(n.Lhs)
                flatten(n.Rhs)
            else
                conjuncts[#conjuncts + 1] = n
            end
        end
        flatten(inner)
        local last = conjuncts[#conjuncts]
        if type(last) == "table" and last.AstType == "CallExpr" then
            local guardName = callTargetName(last.Base)
            if guardName and isGuardName(guardName, registry) then
                local locals, refs, guardedSet = {}, {}, {}
                for _, a in ipairs(last.Arguments or {}) do
                    if isVarRef(a) then
                        locals[#locals + 1] = a.Name
                        guardedSet[a.Name] = true
                    elseif chainRefKeyFwd then
                        local rawKey = chainRefKeyFwd(a)
                        if rawKey then
                            local key = canonChainKeyFwd
                                and canonChainKeyFwd(rawKey) or rawKey
                            refs[#refs + 1] = key
                            guardedSet[key] = true
                        end
                    end
                end
                if #locals > 0 or #refs > 0 then
                    for i = 1, #conjuncts - 1 do
                        local c = conjuncts[i]
                        local ok = false
                        if type(c) == "table"
                            and (c.AstType == "VarExpr" or c.AstType == "MemberExpr") then
                            local chain = callTargetName(c)
                            if chain and not guardedSet[chain] then
                                ok = guardName == chain
                                    or guardName:sub(1, #chain + 1) == (chain .. ".")
                            end
                        end
                        if not ok then return nil end
                    end
                    return { kind = "untaint-else", locals = locals, refs = refs }
                end
            end
        end
    end
    return nil
end

-- Unsafe probe order (round-7, generalized round-7c): a possibly-secret ref
-- truth-tested EARLIER in an and/or chain than a guard call probing that same
-- ref. `x and issecretvalue(x)` throws when x IS secret ("attempt to perform
-- boolean test on ...") — the exact case the probe exists for; so do the
-- disjunct form `not x or issecretvalue(x)` and the dotted form
-- `t.f and issecretvalue(t.f)`. Runs from walkExpr's BinopExpr handling so it
-- fires in every expression context (conditions, assignment RHS, returns).
-- Nested/parenthesized sub-chains revisit the same terms during recursion —
-- dedupe by (file, line, message) so each defect emits once. One finding per
-- line: two distinct refs mis-probed on one line collapse into one finding.
local PROBE_ORDER_MSG = "tainted local truth-tested before its secret probe"
    .. " — a secret throws on the truth-test; probe first, unconditionally"
local SECRET_TEST_MSG = "truth-test dominated by a probe that proved the value"
    .. " SECRET — the test throws on every path that reaches it; invert the"
    .. " probe polarity"
-- Round-8: a truth-test of a possibly-secret ref throws in-game whether or
-- not a probe appears anywhere (the round-6b "existence tests are
-- engine-legal" premise was falsified live in round-7).  Chains that DO probe
-- later keep the more actionable PROBE_ORDER_MSG; this message covers chains
-- that never probe at all (`if updateInfo and updateInfo.isFullUpdate then`
-- with a secret event payload).
local TAINTED_TRUTH_TEST_MSG = "possibly-secret value truth-tested with no"
    .. " issecretvalue probe — a secret throws on the truth-test; probe"
    .. " first, unconditionally"
local LUA_KEYWORDS = {
    ["and"] = true, ["break"] = true, ["do"] = true, ["else"] = true,
    ["elseif"] = true, ["end"] = true, ["false"] = true, ["for"] = true,
    ["function"] = true, ["if"] = true, ["in"] = true, ["local"] = true,
    ["nil"] = true, ["not"] = true, ["or"] = true, ["repeat"] = true,
    ["return"] = true, ["then"] = true, ["true"] = true, ["until"] = true,
    ["while"] = true,
}
-- Decode a raw string-literal spelling (quotes included) to its runtime
-- VALUE (round-10d): short strings with Lua 5.1 escapes (single-char +
-- \ddd decimal) and long-bracket strings. nil for spellings this decoder
-- cannot prove (\x is 5.2+, malformed escapes) — callers fall back to
-- "no sound identity".
local STRING_ESCAPES = {
    a = "\a", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t", v = "\v",
    ["\\"] = "\\", ['"'] = '"', ["'"] = "'", ["\n"] = "\n",
}
local function decodeStringLiteral(raw)
    if type(raw) ~= "string" or #raw < 2 then return nil end
    local q = raw:sub(1, 1)
    if q == '"' or q == "'" then
        if raw:sub(-1) ~= q then return nil end
        local body = raw:sub(2, -2)
        if not body:find("\\", 1, true) then return body end
        local out, i, n = {}, 1, #body
        while i <= n do
            local c = body:sub(i, i)
            if c == "\\" then
                local nxt = body:sub(i + 1, i + 1)
                if STRING_ESCAPES[nxt] then
                    out[#out + 1] = STRING_ESCAPES[nxt]
                    i = i + 2
                elseif nxt:match("%d") then
                    local digits = body:match("^(%d%d?%d?)", i + 1)
                    local code = tonumber(digits)
                    if not code or code > 255 then return nil end
                    out[#out + 1] = string.char(code)
                    i = i + 1 + #digits
                else
                    return nil
                end
            else
                out[#out + 1] = c
                i = i + 1
            end
        end
        return table.concat(out)
    end
    local eqs = raw:match("^%[(=*)%[")
    if eqs then
        local close = "]" .. eqs .. "]"
        if raw:sub(-#close) ~= close then return nil end
        local body = raw:sub(3 + #eqs, -(#close + 1))
        -- Lua drops one newline immediately after the opening bracket.
        if body:sub(1, 1) == "\n" then body = body:sub(2) end
        return body
    end
    return nil
end
-- Constant-fold a numeric index expression: literals, unary minus, and
-- arithmetic over foldable operands evaluate to ONE runtime key —
-- `c[-1]`, `c[1+1]`, `c[2^10]` are as recordable as `c[2]`.
local function foldNumericIndex(idx)
    idx = stripParens(idx)
    if type(idx) ~= "table" then return nil end
    if idx.AstType == "NumberExpr" then
        return tonumber(idx.Value and idx.Value.Data)
    end
    if idx.AstType == "UnopExpr" and idx.Op == "-" then
        local v = foldNumericIndex(idx.Rhs)
        return v and -v
    end
    if idx.AstType == "BinopExpr" then
        local a = foldNumericIndex(idx.Lhs)
        local b = a and foldNumericIndex(idx.Rhs)
        if not b then return nil end
        local op = idx.Op
        if op == "+" then return a + b end
        if op == "-" then return a - b end
        if op == "*" then return a * b end
        if op == "/" then return a / b end
        if op == "%" then return a % b end
        if op == "^" then return a ^ b end
        return nil
    end
    return nil
end
-- ONE bracket-index literal's canonical segment spelling — the SINGLE
-- authority chainRefKey, chainSegDescriptor and constructorEntrySuffix all
-- share, so recorded-key and read-key spellings cannot drift (round-10d:
-- boolean, negative/arithmetic numeric, and escaped-string keys evaded
-- detection because each site canonicalized its own subset).
--   * identifier-valued strings fold to the dot form (`t["f"]` == `t.f`);
--   * other strings %q-quote their DECODED value;
--   * numbers canonicalize via tostring, with a round-trip guard on
--     FOLDED results (tostring may collapse 0.1+0.2 onto the DIFFERENT
--     runtime key 0.3 — reject rather than unify distinct slots);
--   * booleans spell as [true]/[false]; NaN never keys (runtime error on
--     write, nil read).
-- nil = no sound stable identity (calls, variables, \x escapes, ...).
local function literalIndexSegment(idx)
    if type(idx) ~= "table" then return nil end
    if idx.AstType == "BooleanExpr" then
        return "[" .. tostring(idx.Value == true) .. "]"
    end
    if idx.AstType == "StringExpr" then
        local s = decodeStringLiteral(idx.Value and idx.Value.Data)
        if s == nil then return nil end
        if s:find("^[%a_][%w_]*$") and not LUA_KEYWORDS[s] then
            return "." .. s
        end
        return "[" .. string.format("%q", s) .. "]"
    end
    local num = foldNumericIndex(idx)
    if not num or num ~= num then return nil end
    -- Lua table keys compare -0 and +0 as the same numeric value, while
    -- tostring preserves the IEEE sign bit for a dynamically folded -0.
    -- Emit the one runtime key spelling directly instead of allowing the
    -- textual canonical form to split an identical table slot.
    if num == 0 then return "[0]" end
    if idx.AstType ~= "NumberExpr" and tonumber(tostring(num)) ~= num then
        return nil
    end
    return "[" .. tostring(num) .. "]"
end
-- Canonical key for a probe-able reference: bare locals, dotted paths, and
-- KEYED chains (`t[1]`, `t["f"]`, `t[k]`) — round-7j; identity made sound
-- round-7k:
--   * EQUIVALENT spellings unify: `t["f"]` keys as `t.f` (identifier string
--     keys use the dot form); number literals canonicalize via tonumber so
--     `t[1]` == `t[1.0]` (and stay distinct from the STRING key `t["1"]`).
--     String keys with escapes/long-string quoting bail to nil.
--   * A VARIABLE index (`t[k]`) is MUTABLE: any impure call can rebind k
--     (upvalue/global), so these keys are marked volatile — recorded state
--     and proofs for them are purged when a call executes (keyIsVolatile /
--     the purge in visit), and proofs crossing an impure subtree are
--     filtered at application.
local function chainRefKey(n)
    n = stripParens(n)
    if type(n) ~= "table" then return nil end
    if n.AstType == "VarExpr" then
        return n.Name, false
    end
    if n.AstType == "MemberExpr" then
        if n.Indexer ~= "." or not (n.Ident and n.Ident.Data) then return nil end
        local base, vol = chainRefKey(n.Base)
        if not base then return nil end
        return base .. "." .. n.Ident.Data, vol
    end
    if n.AstType == "IndexExpr" then
        local base, vol = chainRefKey(n.Base)
        if not base then return nil end
        local idx = stripParens(n.Index)
        if type(idx) ~= "table" then return nil end
        if idx.AstType == "VarExpr" then
            -- Volatility is carried IN the key via a "~" marker prefix
            -- (round-7k'), never inferred from the key's shape — a literal
            -- like `t[9e999]` canonicalizes through tostring(inf) to
            -- "t[inf]", which a shape heuristic would misclassify as a
            -- variable index and wrongly purge. "~" cannot appear in any
            -- literal-derived key, so the namespaces cannot collide.
            local pre = (base:sub(1, 1) == "~") and "" or "~"
            return pre .. base .. "[" .. idx.Name .. "]", true -- volatile
        end
        local seg = literalIndexSegment(idx)
        if seg then return base .. seg, vol end
        return nil
    end
    return nil
end
chainRefKeyFwd = chainRefKey

-- ONE segment's canonical spelling for a MemberExpr/IndexExpr node —
-- MUST mirror chainRefKey's canonicalization exactly (identifier string
-- keys fold to the dot form, numbers via tostring(tonumber)) so read
-- segments compare equal to recorded-key segments (splitKeySegments).
-- "*" = no sound stable identity (variable/call index, escaped strings,
-- ':' indexer): matches anything in volatilePrefixTainted.
local function chainSegDescriptor(n)
    if n.AstType == "MemberExpr" then
        if n.Indexer == "." and n.Ident and n.Ident.Data then
            return "." .. n.Ident.Data
        end
        return "*"
    end
    if n.AstType == "IndexExpr" then
        local idx = stripParens(n.Index)
        if type(idx) ~= "table" then return "*" end
        return literalIndexSegment(idx) or "*"
    end
    return "*"
end
chainSegDescriptorFwd = chainSegDescriptor

-- Volatile keys are marked structurally by chainRefKey with a "~" prefix.
local function keyIsVolatile(key)
    return key:sub(1, 1) == "~"
end
-- Does this subtree execute any call that could mutate a variable index?
-- Guard probes and restriction gates are pure C-side predicates; everything
-- else (unknown calls, method calls, call sugar) is assumed impure.
local function exprHasImpureCall(n, registry)
    n = stripParensFwd and stripParensFwd(n) or n
    if type(n) ~= "table" then return false end
    local t = n.AstType
    if t == "CallExpr" or t == "StringCallExpr" or t == "TableCallExpr" then
        local name = callTargetName(n.Base)
        if not (name and (isGuardName(name, registry) or registry:isRestrictionGate(name))) then
            return true
        end
        -- pure call: still scan its arguments
        for _, a in ipairs(n.Arguments or {}) do
            if exprHasImpureCall(a, registry) then return true end
        end
        return false
    end
    if t == "Function" then return false end -- not called here, only defined
    for _, k in ipairs({ "Lhs", "Rhs", "Base", "Index", "Inner" }) do
        if n[k] and exprHasImpureCall(n[k], registry) then return true end
    end
    if t == "ConstructorExpr" then
        for _, entry in ipairs(n.EntryList or {}) do
            if entry.Key and exprHasImpureCall(entry.Key, registry) then return true end
            if entry.Value and exprHasImpureCall(entry.Value, registry) then return true end
        end
    end
    if n.Arguments then
        for _, a in ipairs(n.Arguments) do
            if exprHasImpureCall(a, registry) then return true end
        end
    end
    return false
end
-- Taint decision for a probe-able reference. Delegates whole to
-- isTaintedRef: its IndexExpr branch (round-9b) already covers keyed
-- chains — full canonical-chain key, contamination markers, volatile
-- prefix aliasing, clean-field parity, base recursion. The old
-- recurse-to-base shortcut here DROPPED recorded keyed-slot taint
-- (`cache[1] = Source(); cache[1] or DEFAULT` read as clean while the
-- dotted equivalent flagged).
local function chainRefTainted(n, taintSet, fieldTaintSet, registry)
    n = stripParens(n)
    if type(n) ~= "table" then return false end
    return isTaintedRef(n, taintSet, fieldTaintSet, registry)
end
local function guardCallRefKeys(c, into)
    for _, a in ipairs(c.Arguments or {}) do
        local key = chainRefKey(a)
        if key then into[key] = true end
    end
end
-- Proof-set algebra over ref keys, with "*" as the GATE wildcard.  Round-8
-- soundness: "*" no longer means "everything" at the consumers — a falsy
-- aura-restriction gate only proves refs whose taint actually rides the aura
-- restriction (event-payload-derived; see provenCovers).  A cooldown-secret
-- or unconditional SecretReturns value is NOT blessed by an aura gate.
local function proofUnion(a, b)
    if a["*"] or b["*"] then return { ["*"] = true } end
    local r = {}
    for k in pairs(a) do r[k] = true end
    for k in pairs(b) do r[k] = true end
    return r
end
local function proofIntersect(a, b)
    if a["*"] then
        local r = {}
        for k in pairs(b) do r[k] = true end
        return r
    end
    if b["*"] then
        local r = {}
        for k in pairs(a) do r[k] = true end
        return r
    end
    local r = {}
    for k in pairs(a) do
        if b[k] then r[k] = true end
    end
    return r
end
-- Polarity-aware proof algebra (round-7e, made sound round-7g): the set of
-- refs PROVEN to have property `mode` when `n` evaluates to `wantTruthy`.
--   mode "safe"   (proven NON-secret):
--     not guard(x) truthy → {x}; guard(x) falsy → {x};
--     gate() falsy → {"*"} (restrictions off; everything safe)
--   mode "secret" (proven SECRET):
--     guard(x) truthy → {x}; not guard(x) falsy → {x}
--   Boolean composition is identical for both modes:
--   truthy(A and B) → truthy(A) ∪ truthy(B)              (both ran truthy)
--   falsy (A or B)  → falsy(A) ∪ falsy(B)                (both ran falsy)
--   falsy (A and B) → falsy(A) ∩ (truthy(A) ∪ falsy(B))  (case split:
--                     A falsy, OR A truthy and B falsy — only proofs common
--                     to both cases hold)
--   truthy(A or B)  → truthy(A) ∩ (falsy(A) ∪ truthy(B))
-- Anything else proves nothing (conservative).
local function prove(n, wantTruthy, registry, mode)
    n = stripParens(n)
    if type(n) ~= "table" then return {} end
    if n.AstType == "UnopExpr" and n.Op == "not" then
        return prove(n.Rhs, not wantTruthy, registry, mode)
    end
    if n.AstType == "BinopExpr" then
        local op = n.Op
        if op == "and" then
            if wantTruthy then
                return proofUnion(prove(n.Lhs, true, registry, mode),
                    prove(n.Rhs, true, registry, mode))
            end
            return proofIntersect(prove(n.Lhs, false, registry, mode),
                proofUnion(prove(n.Lhs, true, registry, mode),
                    prove(n.Rhs, false, registry, mode)))
        elseif op == "or" then
            if not wantTruthy then
                return proofUnion(prove(n.Lhs, false, registry, mode),
                    prove(n.Rhs, false, registry, mode))
            end
            return proofIntersect(prove(n.Lhs, true, registry, mode),
                proofUnion(prove(n.Lhs, false, registry, mode),
                    prove(n.Rhs, true, registry, mode)))
        end
        return {}
    end
    if n.AstType == "CallExpr" then
        local wantGuardPolarity = (mode == "secret") and wantTruthy
            or (mode ~= "secret" and not wantTruthy)
        if wantGuardPolarity then
            local name = callTargetName(n.Base)
            if name then
                if isGuardName(name, registry) then
                    local s = {}
                    guardCallRefKeys(n, s)
                    return s
                elseif mode ~= "secret" and registry:isRestrictionGate(name) then
                    return { ["*"] = true }
                end
            end
        end
    end
    return {}
end
-- Root local name of a canonical ref key ("t.f" → "t", "~t[k]" → "t").
local function keyRootName(key)
    if key:sub(1, 1) == "~" then key = key:sub(2) end
    return key:match("^([%w_]+)")
end
-- Rewrite a chainRefKey through the handler's table-alias map (round-8d):
-- "info.cd" → "updateInfo.cd" when aliasCanon[info] = "updateInfo", so
-- provenance lookups match the canonical field keys.
local function canonChainKey(key)
    local ctx = fnEventCtx
    if not ctx then return key end
    local pre, k = "", key
    if k:sub(1, 1) == "~" then pre, k = "~", k:sub(2) end
    -- Fixpoint rewrite with cycle detection: root names map through
    -- aliasCanon (targets may be CHAINS
    -- since round-9f: `local sub = updateInfo.sub`), then the LONGEST
    -- matching chainAlias prefix maps slot-spelled chains onto the table
    -- they hold (`updateInfo.sub.cd` → `t2.cd` after `updateInfo.sub = t2`)
    -- — LIVE unification, so writes and reads through either spelling land
    -- on one key no matter which side mutates later.
    local seen = {}
    while not seen[k] do
        seen[k] = true
        local changed = false
        local root, rest = k:match("^([%w_]+)(.*)$")
        if root and ctx.aliasCanon and ctx.aliasCanon[root]
            and ctx.aliasCanon[root] ~= root then
            k = ctx.aliasCanon[root] .. rest
            changed = true
        end
        if ctx.chainAlias then
            -- DESCENDANTS only — the exact slot key stays raw: the slot's
            -- own value is a snapshot (a scalar copied out of the source
            -- does not track later source writes), while table CONTENTS
            -- reached THROUGH the slot share identity with the source.
            local bestP, bestT
            for p2, tgt in pairs(ctx.chainAlias) do
                if (k:sub(1, #p2 + 1) == p2 .. "."
                    or k:sub(1, #p2 + 1) == p2 .. "[")
                    and (not bestP or #p2 > #bestP) then
                    bestP, bestT = p2, tgt
                end
            end
            if bestP and bestT ~= bestP then
                k = bestT .. k:sub(#bestP + 1)
                changed = true
            end
        end
        if not changed then break end
    end
    return pre .. k
end
canonChainKeyFwd = canonChainKey

local function copySafeRefs()
    local r = {}
    for k in pairs(safeRefSet or {}) do r[k] = true end
    return r
end

local function markSafeRefs(refs)
    if not refs then return end
    safeRefSet = safeRefSet or {}
    for _, key in ipairs(refs) do safeRefSet[key] = true end
end

-- Rebinding a root invalidates every proof under it.  Any variable rebind
-- also invalidates volatile-key proofs because that variable may be the key
-- captured in `~t[k]`.
local function invalidateSafeRoot(name)
    if not safeRefSet then return end
    for key in pairs(safeRefSet) do
        local plain = key:sub(1, 1) == "~" and key:sub(2) or key
        if plain:match("^([%w_]+)") == name or key:sub(1, 1) == "~" then
            safeRefSet[key] = nil
        end
    end
end

local function invalidateSafeKey(key)
    if not (safeRefSet and key) then return end
    key = canonChainKey(key)
    local dot, bracket = key .. ".", key .. "["
    for proven in pairs(safeRefSet) do
        if proven == key or proven:sub(1, #dot) == dot
            or proven:sub(1, #bracket) == bracket then
            safeRefSet[proven] = nil
        end
    end
end

purgeMutableSafeRefs = function(expr, registry)
    if safeRefSet and next(safeRefSet) and exprHasImpureCall(expr, registry) then
        for key in pairs(safeRefSet) do safeRefSet[key] = nil end
    end
end
-- Root local name of an arbitrary member/bracket chain expression, keyable
-- or not ("updateInfo.sub[k]" → "updateInfo"); nil for non-chain bases.
local function chainRootName(n)
    n = stripParens(n)
    while type(n) == "table"
        and (n.AstType == "MemberExpr" or n.AstType == "IndexExpr") do
        n = stripParens(n.Base)
    end
    if type(n) == "table" and n.AstType == "VarExpr" then return n.Name end
    return nil
end
-- Is this ref's taint derived from the current handler's secret EVENT
-- payload?  Event payloads are the aura-restricted taint class — the only
-- class the configured restriction gates (ShouldAurasBeSecret + wrappers)
-- actually govern.  Function-source taint (cooldown-restricted /
-- unconditional SecretReturns APIs) is NOT payload-rooted, so a falsy aura
-- gate proves nothing about it (round-8; previously "*" blessed everything).
-- A FIELD of a payload table whose taint was assigned from an independent
-- source (`updateInfo.cd = C_Spell.GetSpellCharges(1)`) is tracked in
-- ctx.independentFields and excluded — root membership alone is not
-- provenance (round-8b).
local function keyIsPayloadRooted(key)
    local ctx = fnEventCtx
    if not (ctx and ctx.payloadNames) then return false end
    -- Gate-ungoverned payload (always-secret event class): the aura gate
    -- does not govern it, so the gate wildcard proof must not cover it.
    if ctx.gateGoverned == false then return false end
    key = canonChainKey(key)
    if ctx.independentFields then
        -- Prefix-aware (round-8c): a deep read through an independent
        -- segment ("updateInfo.cd.sub" when "updateInfo.cd" is independent)
        -- carries that segment's non-payload taint.
        local k = key
        if k:sub(1, 1) == "~" then k = k:sub(2) end
        if ctx.independentFields[k] then return false end
        for i = #k, 1, -1 do
            local c = k:sub(i, i)
            if (c == "." or c == "[")
                and ctx.independentFields[k:sub(1, i - 1)] then
                return false
            end
        end
    end
    local root = keyRootName(key)
    if root and ctx.aliasPoisoned and ctx.aliasPoisoned[root] then return false end
    return (root and ctx.payloadNames[root]) or false
end
-- Does the proof set cover this ref key?  Direct per-key proofs always do;
-- the gate wildcard covers only payload-rooted (aura-class) taint.
local function provenCovers(proven, key)
    if proven[key] then return true end
    if proven["*"] then return keyIsPayloadRooted(key) end
    return false
end
detectUnsafeProbeOrder = function(expr, taintSet, fieldTaintSet, findings, registry, filePath, topTested)
    -- Lua evaluates boolean chains strictly LEFT-TO-RIGHT regardless of
    -- and/or mixing or parenthesization, so soundness needs one ordered walk
    -- over the whole tree — flattening a single operator level misses refs
    -- and guard calls inside nested sub-chains (`(x or y) and guard(x)`,
    -- `x and (guard(x) or y)`). truthTested accumulates every ref that some
    -- earlier and/or position truth-tests; each guard call checks its args
    -- against everything accumulated so far. PATH SENSITIVITY (round-7e):
    -- a later position only executes when every completed earlier operand
    -- resolved the way the chain needs (and→truthy, or→falsy), so proofs
    -- from those polarities (`not issecretvalue(x) and x`,
    -- `issecretvalue(x) or (x and ...)`) suppress the finding — those
    -- truth-tests are dominated by a probe and cannot throw.
    -- MUST run once per FULL statement-level expression (walkExprTop /
    -- walkConditionExpr), never per binop node: scanning a nested sub-chain
    -- without its dominating guards reintroduces the false positive.
    local truthTested = {}
    local proven = {}
    local provenSecret = {}
    -- key → line of its FIRST unproven truth-test (round-8); emission is
    -- deferred to the end of the scan so a chain that probes later reports
    -- once, at the guard, as PROBE_ORDER_MSG.
    local pendingTaintedTests = {}
    -- key → true once some guard call in this expression probed it.
    local probedKeys = {}
    local function emitOnce(line, msg)
        for i = #findings, 1, -1 do
            local f = findings[i]
            if f.file == filePath and f.line == line and f.message == msg then
                return
            end
        end
        emit(findings, filePath, line, 1, "<truthiness>",
            "<tainted-local>", msg)
    end
    local function checkGuardCall(c)
        local guardName = callTargetName(c.Base)
        if not (guardName and isGuardName(guardName, registry)) then return false end
        for _, a in ipairs(c.Arguments or {}) do
            local key = chainRefKey(a)
            if key then
                probedKeys[key] = true
                if truthTested[key]
                    and not provenCovers(proven, key)
                    and chainRefTainted(a, taintSet, fieldTaintSet, registry) then
                    emitOnce(nodeLine(c), PROBE_ORDER_MSG)
                end
            end
        end
        return true
    end
    -- testedCtx: whether a bare ref at this position gets truth-tested.
    -- and/or operands and `not` operands are always tested internally
    -- (whatever the outer consumer does); comparison/arith operands and
    -- call arguments are consumed as VALUES — the comparison/sink rules
    -- own those — but sub-chains inside them still self-test, so descend.
    -- chainCtx (round-8): true only for and/or OPERAND positions — the
    -- positions the round-6b exemption silenced.  Bare-condition refs and
    -- `not` operands already emit through walkConditionExpr / the unop rule,
    -- so the deferred TAINTED_TRUTH_TEST emission is scoped to chain
    -- positions to avoid double-reporting one defect under two messages.
    local function visit(n, testedCtx, chainCtx)
        n = stripParens(n)
        if type(n) ~= "table" then return end
        local t = n.AstType
        if t == "BinopExpr" then
            local op = n.Op
            if op == "and" or op == "or" then
                visit(n.Lhs, true, true)
                -- Later positions run only when the Lhs resolved and→truthy
                -- / or→falsy: harvest what that polarity proves — BOTH ways
                -- (round-7g: `issecretvalue(x) and ...` proves x SECRET in
                -- the continuation; testing it there throws on every path
                -- that reaches the test). SCOPE the proofs to this node's
                -- Rhs and roll them back after (round-7f): a proof harvested
                -- inside one branch does NOT hold in sibling branches of an
                -- ancestor — reaching `... or (x and guard(x))` means the
                -- guarded Lhs was FALSY, i.e. x may be secret there. Proofs
                -- that legitimately extend further are re-derived by the
                -- ancestor's own prove() over its whole Lhs subtree.
                local safeProofs = prove(n.Lhs, op == "and", registry, "safe")
                local secretProofs = prove(n.Lhs, op == "and", registry, "secret")
                -- Volatile (variable-indexed) proofs are unsound across an
                -- impure call inside the proving subtree — the call may have
                -- rebound the index variable AFTER the probe ran
                -- (`(not issecretvalue(t[k]) and Mutate()) and t[k]`).
                if exprHasImpureCall(n.Lhs, registry) then
                    for k in pairs(safeProofs) do
                        if keyIsVolatile(k) then safeProofs[k] = nil end
                    end
                    for k in pairs(secretProofs) do
                        if keyIsVolatile(k) then secretProofs[k] = nil end
                    end
                end
                local addedSafe, addedSecret = {}, {}
                for k in pairs(safeProofs) do
                    if not proven[k] then
                        proven[k] = true
                        addedSafe[#addedSafe + 1] = k
                    end
                end
                for k in pairs(secretProofs) do
                    if not provenSecret[k] then
                        provenSecret[k] = true
                        addedSecret[#addedSecret + 1] = k
                    end
                end
                visit(n.Rhs, testedCtx, true)
                for i = 1, #addedSafe do proven[addedSafe[i]] = nil end
                for i = 1, #addedSecret do provenSecret[addedSecret[i]] = nil end
            else
                visit(n.Lhs, false)
                visit(n.Rhs, false)
            end
        elseif t == "UnopExpr" then
            -- `not` truth-tests its operand; `-`/`#` consume it as a VALUE
            -- (the arith rule owns those) — chains inside still self-test.
            visit(n.Rhs, n.Op == "not")
        elseif t == "CallExpr" then
            -- Guard args are read by the (C-side-safe) probe, not
            -- truth-tested. Non-guard call args are value reads (no
            -- recording), but chains inside them still self-test. The call
            -- BASE is evaluated too (`(cond and fnA or fnB)(x)`).
            if not checkGuardCall(n) then
                visit(n.Base, false)
                for _, a in ipairs(n.Arguments or {}) do
                    visit(a, false)
                end
                -- Impure call: it may rebind any variable index, so
                -- volatile keyed state is no longer trustworthy (round-7k).
                local name = callTargetName(n.Base)
                if not (name and registry:isRestrictionGate(name)) then
                    for k in pairs(truthTested) do
                        if keyIsVolatile(k) then truthTested[k] = nil end
                    end
                    for k in pairs(proven) do
                        if keyIsVolatile(k) then proven[k] = nil end
                    end
                    for k in pairs(provenSecret) do
                        if keyIsVolatile(k) then provenSecret[k] = nil end
                    end
                end
            else
                -- Guard call: probe-able args (bare/dotted/keyed refs) are
                -- safely read by the probe, but a CHAIN argument still
                -- self-tests before the probe sees it.
                for _, a in ipairs(n.Arguments or {}) do
                    if not chainRefKey(a) then
                        visit(a, false)
                    end
                end
            end
        elseif t == "StringCallExpr" or t == "TableCallExpr" then
            -- Call sugar (`f"s"`, `f{ ... }`): base and argument are
            -- evaluated like any call — and it is an impure call, so
            -- volatile keyed state is purged (round-7k).
            visit(n.Base, false)
            for _, a in ipairs(n.Arguments or {}) do
                visit(a, false)
            end
            for k in pairs(truthTested) do
                if keyIsVolatile(k) then truthTested[k] = nil end
            end
            for k in pairs(proven) do
                if keyIsVolatile(k) then proven[k] = nil end
            end
            for k in pairs(provenSecret) do
                if keyIsVolatile(k) then provenSecret[k] = nil end
            end
        elseif t == "ConstructorExpr" then
            -- Table constructor entries are value reads; chains inside
            -- them still self-test (`{ x and issecretvalue(x) }`).
            for _, entry in ipairs(n.EntryList or {}) do
                if entry.Key then visit(entry.Key, false) end
                if entry.Value then visit(entry.Value, false) end
            end
        elseif t == "VarExpr" or t == "MemberExpr" or t == "IndexExpr" then
            local key = chainRefKey(n)
            if key and testedCtx then
                -- Safe-proof wins (round-7g): under an active safe-proof the
                -- test either cannot throw, or — when a secret-proof is
                -- ALSO active — the path is infeasible and the test never
                -- executes (`(a and guard(x)) and (guard(x) or x)`: x is
                -- reached only via guard-falsy inside a guard-truthy
                -- continuation). Either way: no throw, no recording.
                if provenCovers(proven, key) then
                    -- dominated-safe or infeasible — nothing to do
                    -- (`(not guard(x) and x) or (guard(x) and ...)` is clean)
                elseif provenSecret[key]
                    and chainRefTainted(n, taintSet, fieldTaintSet, registry) then
                    -- Wrong-polarity domination (round-7g): this truth-test
                    -- executes exactly on paths where the probe returned
                    -- "secret" — a certain throw. (`issecretvalue(x) and x`,
                    -- `not issecretvalue(x) or x`.)
                    emitOnce(nodeLine(n), SECRET_TEST_MSG)
                else
                    truthTested[key] = true
                    -- Round-8: an unproven truth-test of a tainted ref in an
                    -- and/or chain throws in-game even if no probe ever
                    -- appears.  Record; emitted after the scan unless a later
                    -- guard call turns it into the probe-order finding.
                    if chainCtx and not pendingTaintedTests[key]
                        and chainRefTainted(n, taintSet, fieldTaintSet, registry) then
                        pendingTaintedTests[key] = nodeLine(n)
                    end
                end
            elseif not key then
                if t == "MemberExpr" then
                    -- Complex base (`(x and guard(x)).field`): the base
                    -- expression is still evaluated. The full unkeyable
                    -- chain can itself be the truth-tested secret read
                    -- (`h[K()].foo or D`), so retain a synthetic identity
                    -- that no guard can accidentally bless.
                    visit(n.Base, false)
                    if testedCtx and chainCtx
                        and chainRefTainted(n, taintSet, fieldTaintSet,
                            registry) then
                        local synth = "~?" .. tostring(nodeLine(n))
                        if not pendingTaintedTests[synth] then
                            pendingTaintedTests[synth] = nodeLine(n)
                        end
                    end
                elseif t == "IndexExpr" then
                    -- Un-keyable index (`(x and guard(x))[Foo()]`): both
                    -- sides are still evaluated.
                    visit(n.Base, false)
                    visit(n.Index, false)
                    -- Round-10d: the read itself is STILL truth-tested in
                    -- chain position, and no guard arg can spell it either
                    -- (probe pairing impossible — chainRefKey nil on both
                    -- sides), so consult the contamination markers/root
                    -- taint directly: `c[K()] = S(); c[K()] or D` throws
                    -- in-game exactly like the keyable spellings. The
                    -- synthetic pending key starts "~?" — unreachable from
                    -- chainRefKey, so probedKeys can never suppress it.
                    if testedCtx and chainCtx
                        and chainRefTainted(n, taintSet, fieldTaintSet,
                            registry) then
                        local synth = "~?" .. tostring(nodeLine(n))
                        if not pendingTaintedTests[synth] then
                            pendingTaintedTests[synth] = nodeLine(n)
                        end
                    end
                end
            end
        end
    end
    -- Tail honesty: the FINAL position of the top-level chain is only
    -- truth-tested when the consumer tests it (if/while conditions do;
    -- assignments/returns/call args consume the VALUE — `local v =
    -- issecretvalue(x) and x` never tests x).
    visit(expr, topTested == true)
    -- Round-8 deferred emission: chain-position truth-tests of tainted refs
    -- that no guard in this expression ever probed.  Sorted for deterministic
    -- finding order.
    local pendingKeys
    for key in pairs(pendingTaintedTests) do
        if not probedKeys[key] then
            pendingKeys = pendingKeys or {}
            pendingKeys[#pendingKeys + 1] = key
        end
    end
    if pendingKeys then
        table.sort(pendingKeys, function(a, b)
            local la, lb = pendingTaintedTests[a], pendingTaintedTests[b]
            if la ~= lb then return la < lb end
            return a < b
        end)
        -- A line already carrying a truthiness-family finding (value-select
        -- at the or, bare-condition truthiness, wrong-polarity, probe-order)
        -- reports the same defect with a more specific message — do not add
        -- the generic one on top of it.
        local coveredLines = {}
        for _, f in ipairs(findings) do
            if f.file == filePath
                and (f.sink == "<truthiness>" or f.sink == "<binop:or>") then
                coveredLines[f.line] = true
            end
        end
        for _, key in ipairs(pendingKeys) do
            if not coveredLines[pendingTaintedTests[key]] then
                emitOnce(pendingTaintedTests[key], TAINTED_TRUTH_TEST_MSG)
            end
        end
    end
end
-- Statement-level expression entry: the normal sink walk runs first, then the
-- ordered probe-order scan over the WHOLE expression (path context intact).
-- Sink walk FIRST (round-8): the deferred tainted-truth-test emission
-- suppresses itself on lines where a more specific truthiness-family finding
-- (value-select at the or, wrong-polarity, probe-order) already landed, so
-- those findings must exist before the deferred pass runs.
-- Value position: the chain tail is NOT truth-tested here (topTested=false).
local function walkExprTop(expr, taintSet, fieldTaintSet, findings, registry, filePath)
    local hadSource = walkExpr(expr, taintSet, fieldTaintSet, findings, registry, filePath)
    detectUnsafeProbeOrder(expr, taintSet, fieldTaintSet, findings, registry, filePath, false)
    purgeMutableSafeRefs(expr, registry)
    return hadSource
end

local function walkNumericForExpr(expr, taintSet, fieldTaintSet, findings,
        registry, filePath)
    local before = #findings
    local hadSource = walkExprTop(expr, taintSet, fieldTaintSet, findings,
        registry, filePath)
    if #findings == before
        and (hadSource
            or isValueTainted(expr, taintSet, fieldTaintSet, registry)) then
        emit(findings, filePath, nodeLine(expr), 1, "<numeric-for>",
            "<tainted-local>", "tainted value used as a numeric-for bound or step")
    end
end

-- Does an ipairs/pairs generator ARGUMENT resolve to an element-secret
-- container call (round-23)? Strips `or`-chain defaults — `Src(u) or {}`
-- iterates the container when present; a plain-ref/constructor default is
-- legal in that position (the container REFERENCE is never secret).
local function orChainHasElementSecretCall(n, registry)
    n = stripParens(n)
    if type(n) ~= "table" then return false end
    if n.AstType == "BinopExpr" and n.Op == "or" then
        return orChainHasElementSecretCall(n.Lhs, registry)
            or orChainHasElementSecretCall(n.Rhs, registry)
    end
    if n.AstType == "CallExpr" then
        local cn = callTargetName(n.Base)
        return (cn and isElementSecretCallName(cn, registry)) or false
    end
    return false
end

-- Loop-HEADER expression walk, hoisted to file scope (round-23):
-- walkStatements sits at Lua 5.1's 60-upvalue ceiling, so the generic-for
-- element handling lives here and this helper REPLACES walkStatements'
-- direct walkNumericForExpr capture (net zero upvalues there).
--
-- Generic-for FP suppression (the reproduced Codex FP): `ipairs(auras)`
-- where auras carries ONLY a contamination marker emitted "tainted value
-- passed to ipairs" via CONTENT_READER_FUNCTIONS + refHasTaintedDescendant
-- — but iterating a READABLE element-secret container is the engine-legal
-- scan idiom; only the yielded ELEMENTS are possibly secret. When the
-- single generator is an ipairs/pairs call whose argument is (1) a ref NOT
-- itself tainted but with marker/descendant evidence, or (2) an
-- element-secret container call (possibly behind an `or`-chain default),
-- the header call node is skipped: each ARGUMENT is walked individually so
-- nested sinks still surface, the content-reader emit never fires, and the
-- returned VALUE-binder name (VariableList position 2) is tainted by the
-- caller AFTER its loop-var shadow-clear. The KEY binder (position 1)
-- stays clean — ipairs indices / pairs keys are plain. A whole-tainted
-- argument (in taintSet / value-tainted chain) keeps the existing header
-- emit: iterating a SECRET reference still throws (E17 pins it).
--
-- Returns: valueVarName (string) when suppression applied and a value
-- binder exists; true when suppression applied with no value binder;
-- nil when the ordinary header walk ran.
local function walkLoopHeaderExprs(t, stmt, taintSet, fieldTaintSet, findings,
        registry, filePath)
    if t == "NumericForStatement" then
        if stmt.Start then walkNumericForExpr(stmt.Start, taintSet, fieldTaintSet, findings, registry, filePath) end
        if stmt.End   then walkNumericForExpr(stmt.End,   taintSet, fieldTaintSet, findings, registry, filePath) end
        if stmt.Step  then walkNumericForExpr(stmt.Step,  taintSet, fieldTaintSet, findings, registry, filePath) end
        return nil
    end
    if t ~= "GenericForStatement" or not stmt.Generators then return nil end
    local gens = stmt.Generators
    local call
    if #gens == 1 then
        local c = stripParens(gens[1])
        if type(c) == "table" and c.AstType == "CallExpr" then
            local gname = callTargetName(c.Base)
            if gname == "ipairs" or gname == "pairs" then call = c end
        end
    end
    local suppressed = false
    local arg = call and call.Arguments and call.Arguments[1]
    if arg then
        local sarg = stripParens(arg)
        local at = type(sarg) == "table" and sarg.AstType or nil
        if at == "VarExpr" or at == "MemberExpr" or at == "IndexExpr" then
            -- Marker-only container ref: the whole ref must NOT be tainted
            -- (a secret reference into ipairs throws — existing emit owns
            -- that), with element/descendant evidence present.
            suppressed = not isTaintedRef(sarg, taintSet, fieldTaintSet, registry)
                and refHasTaintedDescendant(sarg, taintSet, fieldTaintSet, registry)
        elseif at then
            -- Direct container call (possibly `or`-defaulted). A chain that
            -- can also YIELD a tainted value keeps the existing emit.
            suppressed = orChainHasElementSecretCall(sarg, registry)
                and not isValueTainted(sarg, taintSet, fieldTaintSet, registry)
        end
    end
    if not suppressed then
        for _, g in ipairs(gens) do
            walkExprTop(g, taintSet, fieldTaintSet, findings, registry, filePath)
        end
        return nil
    end
    -- Suppressed header: walk the argument subtrees only (nested sinks
    -- still surface; the ipairs/pairs call node itself is never walked, so
    -- the content-reader rule cannot fire).
    for _, a in ipairs(call.Arguments) do
        walkExprTop(a, taintSet, fieldTaintSet, findings, registry, filePath)
    end
    local vlist = stmt.VariableList
    local valueVar = vlist and vlist[2] and vlist[2].Name
    return valueVar or true
end

--- Walk an expression for unsafe sinks consuming tainted locals.
--- Returns true if the expression itself is (or contains) a source call —
--- the caller uses this to decide whether the assigned-to variable is tainted.
--- fieldTaintSet tracks tainted table fields keyed by "<tableLocal>.<field>".
walkExpr = function(expr, taintSet, fieldTaintSet, findings, registry, filePath)
    if type(expr) ~= "table" then return false end
    local t = expr.AstType
    if not t then return false end

    if t == "Parentheses" then
        return walkExpr(expr.Inner, taintSet, fieldTaintSet, findings, registry, filePath)
    end

    if t == "Function" then
        -- Closure body. This is still intra-file and non-interprocedural, but
        -- tainted locals can be captured as upvalues by callbacks and sort
        -- predicates, so inherit the current scope and clear function params.
        walkFunctionBody(expr, taintSet, fieldTaintSet, findings, registry, filePath, nil)
        return false
    end

    if t == "DotsExpr" then
        -- Bare `...` inside a detected secret-event handler whose configured
        -- payload positions land in the vararg carries secrets (round-6b:
        -- `print(...)` / `{...}` leaked unflagged). The LocalStatement /
        -- AssignmentStatement spill rules intercept `x, y = ...` BEFORE this,
        -- so position-precise mapping still wins there.
        local ctx = fnEventCtx
        return (ctx and ctx.varargSecret and not ctx.suppressSpill) and true or false
    end

    if t == "BinopExpr" then
        local op = expr.Op
        -- Value-consuming ops (comparison/arith/concat) see and/or value flow
        -- (`(x and x.f) > 0` reads the field); and/or themselves keep the
        -- plain-ref check so the existence-test exemptions below stay narrow.
        local refCheck = (COMPARISON_OPS[op] or ARITH_OPS[op]) and isValueTainted or isTaintedRef
        local lhsTainted = refCheck(expr.Lhs, taintSet, fieldTaintSet, registry)
        local rhsTainted = refCheck(expr.Rhs, taintSet, fieldTaintSet, registry)
        -- Recurse FIRST: a direct source-call operand (`icon:GetAlpha() > 0.5`
        -- with no intermediate local) returns "contains source" and must count
        -- as a tainted operand — assignment-only detection missed these.
        -- Direct pcall/xpcall operands truncate to the clean ok boolean.
        local lhsHadSource = walkExpr(expr.Lhs, taintSet, fieldTaintSet, findings, registry, filePath)
            and not isProtectedCallExpr(expr.Lhs)
        local rhsHadSource = walkExpr(expr.Rhs, taintSet, fieldTaintSet, findings, registry, filePath)
            and not isProtectedCallExpr(expr.Rhs)
        -- DEFERRED TRUTH-TEST rule for and/or: detectUnsafeProbeOrder owns
        -- plain tainted REFS (VarExpr/MemberExpr/IndexExpr), because it can
        -- distinguish probe-dominated paths from an unproven truth-test.
        -- Suppress the duplicate binop emission here while isValueTainted
        -- still carries the yielded taint to assignments, sinks and value
        -- consumers. Direct SOURCE CALL operands have no stable ref key for
        -- that pass, so this walker emits their inline truth-test unless the
        -- call is existence-guarded (`C_X.Fn and C_X.Fn(id)`).
        -- Comparisons, arithmetic, concat and every nested sink still emit.
        local emitLhsTainted, emitRhsTainted = lhsTainted, rhsTainted
        local emitLhsSource,  emitRhsSource  = lhsHadSource, rhsHadSource
        if op == "and" or op == "or" then
            -- Probe-order scanning runs ONCE per statement-level expression
            -- (walkExprTop / walkConditionExpr), NOT here: scanning a nested
            -- sub-chain in isolation loses the dominating guards collected
            -- by outer positions and re-creates path-insensitive FPs.
            local lhs, rhs = stripParens(expr.Lhs), stripParens(expr.Rhs)
            -- Keyed refs (`t[1]`) are plain references too (round-9d) —
            -- probe ordering for them is detectUnsafeProbeOrder's job, same
            -- as dotted refs.
            local function isPlainRef(e)
                return type(e) == "table"
                    and (e.AstType == "VarExpr" or e.AstType == "MemberExpr"
                        or e.AstType == "IndexExpr")
            end
            if isPlainRef(lhs) then emitLhsTainted = false end
            if isPlainRef(rhs) then emitRhsTainted = false end
            if op == "and" and rhsHadSource
                and type(rhs) == "table" and rhs.AstType == "CallExpr" then
                local calleeName = callTargetName(rhs.Base)
                if calleeName and isExistenceGuardFor(lhs, calleeName) then
                    emitRhsSource = false
                end
            end
            -- Value-select idiom (round-7b): `cond and taintedX or fallback`
            -- — when cond is truthy the `or` truth-tests taintedX's VALUE,
            -- and a secret throws on that truth-test (the gse_compat
            -- spellID-slot pick shipped exactly this). The plain-ref
            -- exemption above must not swallow it: the yielded ref is not an
            -- existence test here, it is the selected value. Emit and point
            -- at if/else. A plain `taintedX or fallback` is handled by the
            -- generic truth-test detector, so this block only owns the
            -- nested and/or value-select diagnostic. PATH SENSITIVITY
            -- (round-7e): the yield only reaches the `or` test
            -- when every earlier conjunct ran truthy — if that polarity
            -- proves the ref non-secret (`not issecretvalue(x) and x or d`,
            -- the canonical SAFE unwrap; `not Gate() and x or d`), suppress.
            if op == "or" and type(lhs) == "table"
                and lhs.AstType == "BinopExpr" and lhs.Op == "and" then
                local yielded = stripParens(lhs.Rhs)
                local key = chainRefKey(yielded)
                if key
                    and chainRefTainted(yielded, taintSet, fieldTaintSet, registry) then
                    local proven = prove(lhs.Lhs, true, registry, "safe")
                    -- Volatile proofs are unsound across an impure call in
                    -- the proving conjuncts (round-7k).
                    if keyIsVolatile(key) and proven[key]
                        and exprHasImpureCall(lhs.Lhs, registry) then
                        proven[key] = nil
                    end
                    if not provenCovers(proven, key) then
                        emit(findings, filePath, nodeLine(expr), 1, "<binop:or>",
                            "<tainted-local>",
                            "tainted value yielded by `and` is truth-tested by `or`"
                            .. " (value-select idiom) — a secret throws; use if/else")
                    end
                end
            end
        end
        if emitLhsTainted or emitRhsTainted or emitLhsSource or emitRhsSource then
            local sinkLabel
            if COMPARISON_OPS[op] then
                sinkLabel = "<comparison>"
            elseif ARITH_OPS[op] then
                sinkLabel = "<arith>"
            else
                sinkLabel = "<binop:" .. (op or "?") .. ">"
            end
            emit(findings, filePath, nodeLine(expr), 1, sinkLabel,
                "<tainted-local>",
                "tainted value used in " .. sinkLabel .. " without guard or unwrap")
        end
        return lhsHadSource or rhsHadSource
    end

    if t == "CallExpr" or t == "StringCallExpr" or t == "TableCallExpr" then
        local name, kind = callTargetName(expr.Base)
        -- A computed call base is an evaluated expression in its own right:
        -- `(cond and A or B)()` and `factory()[key]()` must not hide nested
        -- sinks or direct source truth-tests.  Plain dotted/bare callees have
        -- a resolvable name and need no base walk.
        if not name and expr.Base then
            walkExpr(expr.Base, taintSet, fieldTaintSet, findings, registry, filePath)
        end
        if name then
            -- pcall/xpcall(<source>, ...): treat the whole call as a source call.
            -- Lua signature: pcall(f, arg1, ...) and xpcall(f, msgh, arg1, ...).
            -- In both cases argument 1 is the function being protected.
            -- If that function is a registered source, the pcall result is tainted.
            if name == "pcall" or name == "xpcall" then
                local fnArg = expr.Arguments and expr.Arguments[1]
                if fnArg then
                    local fnName = callTargetName(fnArg)
                    if fnName and registry:isSource(fnName) then
                        -- Walk remaining arguments for nested sinks
                        for i = 2, #(expr.Arguments or {}) do
                            walkExpr(expr.Arguments[i], taintSet, fieldTaintSet, findings, registry, filePath)
                        end
                        return true  -- result is tainted (conservative: includes the ok bool)
                    end
                end
                -- fnArg is not a source — fall through to normal argument recursion
            end
            -- Unique local same-file wrappers carry a compact parameter /
            -- return summary.  Evaluate each actual argument once, surface
            -- callee-side unsafe parameter use at this call site, and map
            -- tainted actuals back through parameter-derived returns.
            local summaryBinder = expr.Base
                and expr.Base.AstType == "VarExpr"
                and expr.Base.Variable
            local summaryModel = summaryBinder and fnEventCtx
                and fnEventCtx.functionSummaries
            local summary, summaryResolved =
                resolveIntraFileFunctionSummary(summaryModel, summaryBinder, expr)
            if summaryResolved then
                local argTainted = {}
                for i, arg in ipairs(expr.Arguments or {}) do
                    local hadSource = walkExpr(arg, taintSet, fieldTaintSet,
                        findings, registry, filePath)
                    if hadSource and isProtectedCallExpr(arg) then
                        hadSource = false
                    end
                    argTainted[i] = hadSource
                        or isValueTainted(arg, taintSet, fieldTaintSet, registry)
                end
                for index in pairs(summary.sinkParams or {}) do
                    if argTainted[index] then
                        emit(findings, filePath, nodeLine(expr), 1,
                            "<call:" .. name .. ">", "<tainted-local>",
                            "tainted argument reaches an unsafe operation in "
                                .. name)
                    end
                end
                if summary.returnSource then return true end
                for index in pairs(summary.returnParams or {}) do
                    if argTainted[index] then return true end
                end
                return false
            end
            -- Source call: walk arguments for nested sinks but do not emit here
            if registry:isSource(name) then
                if expr.Arguments then
                    for _, a in ipairs(expr.Arguments) do
                        walkExpr(a, taintSet, fieldTaintSet, findings, registry, filePath)
                    end
                end
                return true
            end
            -- Safe sink: tainted args are acceptable; still recurse into
            -- argument expressions to catch any nested unsafe sub-expressions
            -- (e.g. frame:SetText(tonumber(x)) — SetText is safe but tonumber is not).
            -- If the function is ALSO secret-returning (e.g. C_StringUtil
            -- formatters), the return value carries taint to the LHS — caller
            -- decides what to do with that based on context.
            if (kind == "method" and registry:isSafeSinkMethod(getMethodNameFromQualified(name))) or
               (kind == "function" and registry:isSafeSinkFunction(name)) then
                if expr.Arguments then
                    for _, a in ipairs(expr.Arguments) do
                        walkExpr(a, taintSet, fieldTaintSet, findings, registry, filePath)
                    end
                end
                return registry:isSecretReturning(name)
            end
            -- Unwrap: emit review finding, but do NOT propagate taint forward
            if registry:isUnwrap(name) then
                findings[#findings + 1] = {
                    file = filePath, line = nodeLine(expr) or 0, col = 1,
                    severity = "review",
                    source_function = name,
                    sink = "<unwrap>",
                    message = "unwrap call site — consider piping to a C-side sink instead",
                    suppressed = false, suppression_reason = nil,
                }
                if expr.Arguments then
                    for _, a in ipairs(expr.Arguments) do
                        walkExpr(a, taintSet, fieldTaintSet, findings, registry, filePath)
                    end
                end
                return false  -- result is non-tainted; do NOT mark as source
            end
            -- select() over the handler vararg: position-precise extraction.
            -- `select(k, ...)` yields vararg values from k on — tainted when
            -- any configured secret position is >= k; `select("#", ...)` is a
            -- COUNT and stays clean (the generic DotsExpr rule above would
            -- otherwise flag it). A DYNAMIC clean index (the canonical
            -- `for i = 1, select("#", ...) do local v = select(i, ...)` loop)
            -- taints the RESULT without flagging the call site — selecting
            -- from the vararg reads no content (round-6b: the fall-through to
            -- the unsafe-builtin walk emitted a reproducible false positive
            -- on that idiom). A TAINTED index still falls through and flags.
            if name == "select" and fnEventCtx and fnEventCtx.varargSecret
                and not fnEventCtx.suppressSpill then
                local kArg = expr.Arguments and expr.Arguments[1]
                local dotsArg = expr.Arguments and expr.Arguments[2]
                if dotsArg and dotsArg.AstType == "DotsExpr" and kArg then
                    local positional = selectVarargTaint(expr, 1)
                    if positional ~= nil
                        and not isTaintedRef(kArg, taintSet, fieldTaintSet, registry) then
                        walkExpr(kArg, taintSet, fieldTaintSet, findings, registry, filePath)
                        return positional
                    end
                end
            end
            -- Unsafe builtin called with a tainted argument
            if UNSAFE_BUILTIN_FUNCTIONS[name] then
                if expr.Arguments then
                    local nArgs = #expr.Arguments
                    for i, a in ipairs(expr.Arguments) do
                        -- Recurse to catch deeper sinks; a direct source-call
                        -- argument (`tostring(icon:GetAlpha())`) is tainted
                        -- too. A protected call spills every return ONLY when
                        -- it is bare in LAST position — `print(pcall(src))`
                        -- hands the secret returns to the builtin. Non-last
                        -- position and parentheses (`print((pcall(src)))`)
                        -- both truncate to the clean ok boolean.
                        local argHadSource = walkExpr(a, taintSet, fieldTaintSet, findings, registry, filePath)
                        if argHadSource and isProtectedCallExpr(a)
                            and (i < nArgs or a.AstType == "Parentheses") then
                            argHadSource = false
                        end
                        -- A bare final select() expands all selected varargs;
                        -- scalar walkExpr only reports its first return.
                        if i == nArgs and a.AstType ~= "Parentheses"
                            and selectVarargTaint(a, nil) then
                            argHadSource = true
                        end
                        if argHadSource
                            or isValueTainted(a, taintSet, fieldTaintSet, registry)
                            or (CONTENT_READER_FUNCTIONS[name]
                                and refHasTaintedDescendant(a, taintSet,
                                    fieldTaintSet, registry)) then
                            emit(findings, filePath, nodeLine(expr), 1, name,
                                "<tainted-local>",
                                "tainted value passed to " .. name)
                        end
                    end
                end
                return false
            end
            -- Secret-returning function that is NOT also a safe sink (e.g. a
            -- user-defined wrapper). Recurse args, then propagate taint via
            -- return so downstream sinks get caught.
            if registry:isSecretReturning(name) then
                if expr.Arguments then
                    for _, a in ipairs(expr.Arguments) do
                        walkExpr(a, taintSet, fieldTaintSet, findings, registry, filePath)
                    end
                end
                return true
            end
            -- Aspect-returning widget getter (api-index secretReturnsForAspect):
            -- the result may be secret when the receiver's aspect has been
            -- secretized. Bare method-name match — receivers are plain locals.
            -- The registry is aspect-stripped for files outside aspect_paths,
            -- so this never fires there.
            if kind == "method"
                and registry:isAspectReturningMethod(getMethodNameFromQualified(name)) then
                if expr.Arguments then
                    for _, a in ipairs(expr.Arguments) do
                        walkExpr(a, taintSet, fieldTaintSet, findings, registry, filePath)
                    end
                end
                return true
            end
        end
        -- Non-source, non-builtin call: recurse into arguments. Round-13
        -- default-reject (backlog item 2): a tainted value handed to an
        -- UNDOCUMENTED method consumer — or to a documented API whose
        -- SecretArguments forbids tainted callers — leaves the taint model
        -- with no evidence it reaches a C sink, so it flags instead of
        -- traversing silently. Plain UNDOCUMENTED function calls stay
        -- traversal-only: unique local helpers resolve via intra-file
        -- summaries above, and cross-file helpers are the documented
        -- non-interprocedural boundary (hand-audit; see .taintrc header).
        if expr.Arguments then
            local nArgs = #expr.Arguments
            for i, a in ipairs(expr.Arguments) do
                local argHadSource = walkExpr(a, taintSet, fieldTaintSet, findings, registry, filePath)
                if argHadSource and isProtectedCallExpr(a)
                    and (i < nArgs or a.AstType == "Parentheses") then
                    argHadSource = false
                end
                if name and (argHadSource
                    or isValueTainted(a, taintSet, fieldTaintSet, registry))
                    -- Registered probes/guards (issecretvalue et al) are the
                    -- sanctioned inspection surface: the doc index stamps
                    -- them SecretArguments=AllowedWhenUntainted (generator
                    -- default), but the runtime accepts tainted probes —
                    -- classifying them as consumers would outlaw the
                    -- probe-first canon idiom itself (including the
                    -- existence-guard shape `issecretvalue and
                    -- issecretvalue(x)`, which bypasses guard recognition).
                    and not isGuardName(name, registry)
                    and not (kind == "method"
                        and isGuardMethodName(name, registry)) then
                    local restriction
                    local rejects = false
                    if kind == "method" then
                        restriction = registry:docArgRestrictionMethod(
                            getMethodNameFromQualified(name))
                        rejects = true
                    else
                        restriction = registry:docArgRestrictionFunction(name)
                        rejects = restriction ~= nil
                    end
                    if rejects then
                        emit(findings, filePath, nodeLine(expr), 1,
                            "<consumer:" .. name .. ">", "<tainted-local>",
                            restriction
                            and ("tainted value passed to " .. name
                                .. " — documented SecretArguments="
                                .. restriction
                                .. ": tainted code cannot pass secrets here")
                            or ("tainted value passed to unknown method consumer "
                                .. name .. " — not an index-documented"
                                .. " secret-accepting sink; route through a"
                                .. " documented C sink or probe first"))
                    end
                end
            end
        end
        return false
    end

    if t == "ConstructorExpr" then
        for _, entry in ipairs(expr.EntryList or {}) do
            if entry.Key then
                local keyHadSource = walkExpr(entry.Key, taintSet, fieldTaintSet,
                    findings, registry, filePath)
                if keyHadSource
                    or isValueTainted(entry.Key, taintSet, fieldTaintSet, registry) then
                    emit(findings, filePath, nodeLine(entry.Key), 1, "<table-key>",
                        "<tainted-local>",
                        "tainted value used as a table-constructor key")
                end
            end
            if entry.Value then
                walkExpr(entry.Value, taintSet, fieldTaintSet,
                    findings, registry, filePath)
            end
        end
        -- The constructor RESULT is the non-secret table reference; entry
        -- provenance is applied at its assignment target.
        return false
    end

    if t == "IndexExpr" then
        local baseHadSource = walkExpr(expr.Base, taintSet, fieldTaintSet,
            findings, registry, filePath)
        local indexHadSource = walkExpr(expr.Index, taintSet, fieldTaintSet,
            findings, registry, filePath)
        if indexHadSource
            or isValueTainted(expr.Index, taintSet, fieldTaintSet, registry) then
            emit(findings, filePath, nodeLine(expr.Index), 1, "<index>",
                "<tainted-local>", "tainted value used as a table index")
        end
        -- Direct-expression element read (round-23): indexing the RESULT of
        -- an element-secret call without ever binding the container
        -- (`Src(u)[1]`) yields a possibly-secret element with no name the
        -- marker machinery could track, so the read itself is the finding.
        -- This is the ONE sanctioned direct emit for the element class —
        -- marker-mediated reads flow through existing consumers only (see
        -- recordElementContainerMarker). Fires in value AND condition
        -- contexts: both route through this walker.
        local elemBase = stripParens(expr.Base)
        if type(elemBase) == "table" and elemBase.AstType == "CallExpr" then
            local elemName = callTargetName(elemBase.Base)
            if elemName and isElementSecretCallName(elemName, registry) then
                emit(findings, filePath, nodeLine(expr), 1, "<element-read>",
                    elemName,
                    "element of a readable secret-content container used without probe")
            end
        end
        -- Indexing a source-returned table carries the source value forward;
        -- a tainted INDEX is consumed here but does not taint the table value.
        return baseHadSource
    end

    if t == "MemberExpr" then
        -- Usually this is a plain name chain and returns false immediately;
        -- computed bases (`factory().field`) still need their source/sink walk.
        return walkExpr(expr.Base, taintSet, fieldTaintSet, findings, registry, filePath)
    end

    if t == "UnopExpr" then
        local rhsTainted = isTaintedRef(expr.Rhs, taintSet, fieldTaintSet, registry)
        -- Direct source-call operand (`not icon:IsShown()`) counts too;
        -- `not pcall(...)` consumes only the clean ok boolean.
        local rhsHadSource = walkExpr(expr.Rhs, taintSet, fieldTaintSet, findings, registry, filePath)
            and not isProtectedCallExpr(expr.Rhs)
        if rhsTainted or rhsHadSource then
            emit(findings, filePath, nodeLine(expr), 1, "<unop:" .. (expr.Op or "?") .. ">",
                "<tainted-local>",
                "tainted value used in unary " .. (expr.Op or "?"))
        end
        return rhsHadSource
    end

    return false
end

-- Mark a variable's taint as INDEPENDENT of the event payload: once a name
-- (payload param or not) is re-tainted from another source, the dispatch
-- untaint below must not clear it — its secret no longer rides the event.
local function markIndependentTaint(varName)
    if fnEventCtx and fnEventCtx.payloadNames then
        fnEventCtx.payloadNames[varName] = nil
        if fnEventCtx.payloadEvents then fnEventCtx.payloadEvents[varName] = nil end
    end
end

local function markPayloadTaint(varName, events)
    local ctx = fnEventCtx
    if not ctx then return end
    ctx.payloadNames[varName] = true
    local copy = {}
    for eventName in pairs(events or ctx.secretEvents or {}) do
        copy[eventName] = true
    end
    ctx.payloadEvents = ctx.payloadEvents or {}
    ctx.payloadEvents[varName] = copy
end

local function payloadEventsForExpr(expr)
    local ctx = fnEventCtx
    if not ctx then return nil end
    expr = stripParens(expr)
    if type(expr) ~= "table" then return nil end
    local root
    if expr.AstType == "VarExpr" then
        root = expr.Name
    elseif expr.AstType == "MemberExpr" or expr.AstType == "IndexExpr" then
        local n = expr
        while type(n) == "table"
            and (n.AstType == "MemberExpr" or n.AstType == "IndexExpr") do
            n = stripParens(n.Base)
        end
        root = type(n) == "table" and n.AstType == "VarExpr" and n.Name or nil
    end
    local src = root and ctx.payloadEvents and ctx.payloadEvents[root]
    if expr.AstType == "ConstructorExpr" then
        src = {}
        for _, entry in ipairs(expr.EntryList or {}) do
            local events = payloadEventsForExpr(entry.Value)
            for eventName in pairs(events or {}) do src[eventName] = true end
        end
    end
    if not src then return nil end
    local copy = {}
    for eventName in pairs(src) do copy[eventName] = true end
    return copy
end

local function payloadEventsForVararg(pos)
    local ctx = fnEventCtx
    if not ctx then return nil end
    local events = {}
    for eventName, positions in pairs(ctx.eventVarargSecrets or {}) do
        if positions[pos] then events[eventName] = true end
    end
    return events
end

local function payloadEventsForSelect(expr, resultIndex)
    local call = stripParens(expr)
    if type(call) ~= "table" or call.AstType ~= "CallExpr"
        or callTargetName(call.Base) ~= "select" then return nil end
    local args = call.Arguments or {}
    if not (args[2] and args[2].AstType == "DotsExpr") then return nil end
    if stringLiteralValue(args[1]) == "#" then return {} end
    if args[1] and args[1].AstType == "NumberExpr" then
        local k = tonumber(args[1].Value and args[1].Value.Data)
        if k and k > 0 then return payloadEventsForVararg(k + resultIndex - 1) end
    end
    return nil
end

-- Does this RHS carry ONLY event-payload taint — a copy of a payload param
-- (`local u = unit`) or a field read off one? Such copies JOIN the dispatch-
-- untaint set instead of being marked independent: `u` must untaint alongside
-- `unit` inside a non-secret dispatch branch (round-6c: the independent mark
-- on plain copies was a reproducible false positive).
local function eventTaintedOnly(expr, taintSet, fieldTaintSet, registry)
    local ctx = fnEventCtx
    if not ctx or not ctx.payloadNames then return false end
    expr = stripParens(expr)
    if type(expr) ~= "table" then return false end
    if expr.AstType == "VarExpr" then
        -- A poisoned (path-ambiguous) name may refer to a non-payload table
        -- on some path — never payload-only (round-8e).
        if ctx.aliasPoisoned and ctx.aliasPoisoned[expr.Name] then return false end
        return ctx.payloadNames[expr.Name] == true
    end
    if expr.AstType == "MemberExpr" or expr.AstType == "IndexExpr" then
        -- Independent-field provenance (round-8c): a read through ANY chain
        -- segment recorded as independent carries NON-payload taint
        -- (`updateInfo.cd = C_Spell.X(...)`; `local cd = updateInfo.cd` must
        -- classify independent, or the copy re-enters the gate-governed
        -- payload class and the aura gate erases cooldown taint).
        -- STABLE bracket segments participate like dotted ones (round-9d —
        -- `updateInfo["foo"]` is a payload read and must stay gate-governed);
        -- a VOLATILE segment has no sound identity: never payload-only.
        local node = expr
        while type(node) == "table"
            and (node.AstType == "MemberExpr" or node.AstType == "IndexExpr") do
            local key, vol = chainRefKey(node)
            if node.AstType == "IndexExpr" and (not key or vol) then
                return false
            end
            if ctx.independentFields and key and not vol then
                if ctx.independentFields[canonChainKey(key)] then
                    return false
                end
            end
            node = node.Base
        end
        if type(node) ~= "table" or node.AstType ~= "VarExpr" then return false end
        if ctx.aliasPoisoned and ctx.aliasPoisoned[node.Name] then return false end
        return ctx.payloadNames[node.Name] == true
    end
    if expr.AstType == "ConstructorExpr" then
        local hasPayload = false
        for _, entry in ipairs(expr.EntryList or {}) do
            local value = entry.Value
            if value and isValueTainted(value, taintSet, fieldTaintSet, registry) then
                if not eventTaintedOnly(value, taintSet, fieldTaintSet, registry) then
                    return false
                end
                hasPayload = true
            end
        end
        return hasPayload
    end
    return false
end

-- Record table-alias bindings for the canonical field-key map (round-8d):
-- a bare tainted-ref copy (`local info = updateInfo`) makes the LHS an alias
-- of the RHS's canonical root; ANY other binding shape clears the alias (the
-- name no longer refers to that table).  Round-8e: a fresh binding resolves
-- prior cross-path ambiguity for the name; copying an AMBIGUOUS (poisoned)
-- name propagates the poison.
local function recordAliasBinding(varName, rhs)
    local ctx = fnEventCtx
    if not ctx then return end
    ctx.aliasCanon = ctx.aliasCanon or {}
    ctx.aliasPoisoned = ctx.aliasPoisoned or {}
    ctx.aliasPoisoned[varName] = nil
    rhs = rhs and stripParens(rhs)
    if type(rhs) == "table" and rhs.AstType == "VarExpr" then
        if ctx.aliasPoisoned[rhs.Name] then
            ctx.aliasCanon[varName] = nil
            ctx.aliasPoisoned[varName] = true
            return
        end
        local canon = ctx.aliasCanon[rhs.Name] or rhs.Name
        if canon ~= varName then
            ctx.aliasCanon[varName] = canon
            return
        end
    end
    ctx.aliasCanon[varName] = nil
end

-- Two-pass variants (round-9d, Lua simultaneous-assignment semantics):
-- `info, other = other, info` evaluates EVERY RHS before ANY LHS binds, so
-- the statement walkers resolve each RHS's alias identity against the
-- PRE-statement maps (resolve...) and apply the bindings afterwards
-- (apply...).  resolve returns nil for non-bare-copy shapes — apply then
-- clears the alias, matching recordAliasBinding.
local function resolveAliasBindingPre(rhs)
    local ctx = fnEventCtx
    if not ctx then return nil end
    rhs = rhs and stripParens(rhs)
    if type(rhs) ~= "table" then return nil end
    if rhs.AstType == "VarExpr" then
        if ctx.aliasPoisoned and ctx.aliasPoisoned[rhs.Name] then
            return { poison = true }
        end
        return { canon = (ctx.aliasCanon and ctx.aliasCanon[rhs.Name]) or rhs.Name }
    end
    -- STABLE chain copies name the table AT that chain (round-9f:
    -- `local sub = updateInfo.sub` — writes/reads via `sub` must land on
    -- the chain's canonical keys or they desynchronize).  Volatile chains
    -- have no sound identity.
    if rhs.AstType == "MemberExpr" or rhs.AstType == "IndexExpr" then
        local key, vol = chainRefKey(rhs)
        if key and not vol then
            local canon = canonChainKey(key)
            -- IDENTITY resolution (round-9g): canonChainKey rewrites
            -- descendants only, but an alias BINDING names the table
            -- identity — follow exact chainAlias hops so `local x =
            -- updateInfo.sub` after `updateInfo.sub = t2` binds x to "t2",
            -- surviving a later slot rebind.
            if ctx.chainAlias then
                local seen = {}
                while not seen[canon] do
                    seen[canon] = true
                    local tgt = ctx.chainAlias[canon]
                    if not tgt or tgt == canon then break end
                    canon = tgt
                end
            end
            local root = keyRootName(canon)
            if root and ctx.aliasPoisoned and ctx.aliasPoisoned[root] then
                return { poison = true }
            end
            return { canon = canon }
        end
    end
    return nil
end
local function applyAliasBindingPre(varName, resolved)
    local ctx = fnEventCtx
    if not ctx then return end
    ctx.aliasCanon = ctx.aliasCanon or {}
    ctx.aliasPoisoned = ctx.aliasPoisoned or {}
    ctx.aliasPoisoned[varName] = nil
    if resolved and resolved.poison then
        ctx.aliasCanon[varName] = nil
        ctx.aliasPoisoned[varName] = true
    elseif resolved and resolved.canon and resolved.canon ~= varName then
        -- A canon whose ROOT is the name being bound is self-referential
        -- (`t2 = t2.sub`) — unrepresentable in a name-keyed map: poison.
        if keyRootName(resolved.canon) == varName then
            ctx.aliasCanon[varName] = nil
            ctx.aliasPoisoned[varName] = true
        else
            ctx.aliasCanon[varName] = resolved.canon
        end
    else
        ctx.aliasCanon[varName] = nil
    end
end

-- Record a symmetric MAY-alias edge.  Exact aliases live in aliasCanon /
-- chainAlias; wildcard locations (`h[*]`) cannot name one definite slot, but
-- a later write through either spelling must remain visible through the
-- other.  Keeping this structural fact separate from field contamination
-- allows a clean table-reference write to become tainted later.
local function recordMayAliasPair(left, right)
    local ctx = fnEventCtx
    if not (ctx and left and right) or left == right then return end
    ctx.chainAliasMay = ctx.chainAliasMay or {}
    local function link(from, to)
        local set = ctx.chainAliasMay[from]
        if not set then
            set = {}
            ctx.chainAliasMay[from] = set
        end
        set[to] = true
    end
    link(left, right)
    link(right, left)
    -- Re-recording after a concrete strong overwrite advances the blocked
    -- epoch; ordinary abstract-transfer replay reuses the live epoch.
    refreshMayAliasEdge(ctx, left, right, true)
    refreshMayAliasEdge(ctx, right, left, true)
    invalidateMayAliasCache(ctx)
end

-- A name being RE-BOUND may be the alias TARGET other spellings resolve to
-- (chainAlias slots, aliasCanon dependents).  The tables those spellings
-- reference live on, but future writes through the re-bound name go to a
-- NEW table in the SAME key namespace — so snapshot the accumulated keys
-- into each dependent's own spelling NOW (the moment the linkage breaks is
-- exactly when the snapshot becomes correct), then unlink (round-9f).
local function mirrorAliasKeys(fromPrefix, toPrefix, fieldTaintSet)
    local ctx = fnEventCtx
    local fdot, fbr = fromPrefix .. ".", fromPrefix .. "["
    local adds = {}
    for k, v in pairs(fieldTaintSet) do
        if v and (k:sub(1, #fdot) == fdot or k:sub(1, #fbr) == fbr) then
            adds[toPrefix .. k:sub(#fromPrefix + 1)] = true
        end
    end
    if next(adds) then invalidateMayAliasCache(ctx) end
    for k in pairs(adds) do fieldTaintSet[k] = true end
    if ctx and ctx.independentFields then
        local madds = {}
        for k in pairs(ctx.independentFields) do
            if k:sub(1, #fdot) == fdot or k:sub(1, #fbr) == fbr then
                madds[toPrefix .. k:sub(#fromPrefix + 1)] = true
            end
        end
        for k in pairs(madds) do ctx.independentFields[k] = true end
    end
end
-- Does an alias target/canon refer to (or reach through) the prefix key?
local function aliasTargetMatches(tgt, prefixKey)
    return tgt == prefixKey
        or tgt:sub(1, #prefixKey + 1) == prefixKey .. "."
        or tgt:sub(1, #prefixKey + 1) == prefixKey .. "["
end
-- Sever may-alias links through a re-bound spelling (round-10d, Codex
-- catch: stale may-links after a rebind read the NEW table's spelling as
-- the old may-target — `if X then h = {cache = c} end; c.foo = S();
-- h = {}; h.cache.foo` flagged provably-clean code). Severs
-- UNCONDITIONALLY at the rebind site: path-sensitivity is owned by the
-- prov snapshot/merge (chainAliasMay is copied per clause and unioned
-- over reachable exits), so a clause-local sever rolls back when another
-- reachable path keeps the link, an all-arms guaranteed replacement
-- sticks, and repeat-body rebinds dominate (repeat merges no entry
-- state). Keys already recorded under a dying spelling may belong to the
-- surviving side's table: snapshot them across (mirrorAliasKeys) exactly
-- when the linkage breaks, mirroring the live-alias break rule (round-9f).
local function severMayAliases(prefixKey, fieldTaintSet)
    local ctx = fnEventCtx
    local may = ctx and ctx.chainAliasMay
    if not may then return end
    local deadSlots
    local changed = false
    for slot, tgts in pairs(may) do
        if aliasTargetMatches(slot, prefixKey) then
            for tgt in pairs(tgts) do
                if not aliasTargetMatches(tgt, prefixKey) then
                    mirrorAliasKeys(slot, tgt, fieldTaintSet)
                end
            end
            deadSlots = deadSlots or {}
            deadSlots[#deadSlots + 1] = slot
        else
            local deadTgts
            for tgt in pairs(tgts) do
                if aliasTargetMatches(tgt, prefixKey) then
                    mirrorAliasKeys(tgt, slot, fieldTaintSet)
                    deadTgts = deadTgts or {}
                    deadTgts[#deadTgts + 1] = tgt
                end
            end
            for _, tgt in ipairs(deadTgts or {}) do
                tgts[tgt] = nil
                changed = true
            end
            if next(tgts) == nil then
                deadSlots = deadSlots or {}
                deadSlots[#deadSlots + 1] = slot
            end
        end
    end
    for _, slot in ipairs(deadSlots or {}) do
        may[slot] = nil
        changed = true
    end
    if changed then
        for slot, versions in pairs(ctx.mayAliasEdgeVersions or {}) do
            local liveTargets = may[slot]
            if not liveTargets then
                ctx.mayAliasEdgeVersions[slot] = nil
            else
                for target in pairs(versions) do
                    if not liveTargets[target] then versions[target] = nil end
                end
                if next(versions) == nil then
                    ctx.mayAliasEdgeVersions[slot] = nil
                end
            end
        end
        for key, slots in pairs(ctx.mayAliasCleanEdges or {}) do
            for slot, targets in pairs(slots) do
                local liveTargets = may[slot]
                if not liveTargets then
                    slots[slot] = nil
                else
                    for target in pairs(targets) do
                        if not liveTargets[target] then targets[target] = nil end
                    end
                    if next(targets) == nil then slots[slot] = nil end
                end
            end
            if next(slots) == nil then ctx.mayAliasCleanEdges[key] = nil end
        end
        invalidateMayAliasCache(ctx)
    end
end
-- When a target spelling breaks (name rebind or slot rebind), its surviving
-- dependents still share the SAME tables — severing them into isolated
-- namespaces loses that (round-9i: after `local a = t2; updateInfo.sub = a;
-- t2 = {}`, `a` and `updateInfo.sub` still alias each other).  Group the
-- dependents by target (shortest first, so subtree targets can chain
-- through their parent group's rep), elect one REPRESENTATIVE per group —
-- mirror the broken namespace's keys into its spelling once — and RELINK
-- the remaining dependents to the rep.
local function relinkBrokenTarget(prefixKey, excludeName, fieldTaintSet)
    local ctx = fnEventCtx
    if not ctx then return end
    local deps = {}
    if ctx.aliasCanon then
        for nm, canon in pairs(ctx.aliasCanon) do
            if nm ~= excludeName and aliasTargetMatches(canon, prefixKey) then
                deps[#deps + 1] = { spelling = nm, target = canon, isName = true }
            end
        end
    end
    if ctx.chainAlias then
        for slot, tgt in pairs(ctx.chainAlias) do
            -- A slot SPELLED under the broken prefix dies with it
            -- (round-9j): it must neither become a representative nor be
            -- relinked-to — its mirrored keys would land in a namespace the
            -- NEW table owns, where a later clean write erases them.  Its
            -- entry drops via the caller's root/descendant sweeps; its own
            -- dependents rescue through their own target groups here.
            if slot ~= prefixKey and aliasTargetMatches(tgt, prefixKey)
                and not aliasTargetMatches(slot, prefixKey)
                and keyRootName(slot) ~= prefixKey then
                deps[#deps + 1] = { spelling = slot, target = tgt, isName = false }
            end
        end
    end
    if #deps == 0 then return end
    table.sort(deps, function(x, y)
        if #x.target ~= #y.target then return #x.target < #y.target end
        -- Prefer NAME reps (stable spellings) at equal target depth.
        if x.isName ~= y.isName then return x.isName end
        return x.spelling < y.spelling
    end)
    local reps = {}
    for _, d in ipairs(deps) do
        if d.isName then
            ctx.aliasCanon[d.spelling] = nil
        else
            ctx.chainAlias[d.spelling] = nil
        end
        local bestT, bestRep
        for t, rep in pairs(reps) do
            if aliasTargetMatches(d.target, t)
                and (not bestT or #t > #bestT) then
                bestT, bestRep = t, rep
            end
        end
        if bestT then
            local newTarget = bestRep .. d.target:sub(#bestT + 1)
            if newTarget ~= d.spelling then
                if d.isName then
                    if keyRootName(newTarget) == d.spelling then
                        ctx.aliasPoisoned = ctx.aliasPoisoned or {}
                        ctx.aliasPoisoned[d.spelling] = true
                    else
                        ctx.aliasCanon[d.spelling] = newTarget
                    end
                elseif not aliasTargetMatches(newTarget, d.spelling) then
                    ctx.chainAlias[d.spelling] = newTarget
                end
            end
        else
            reps[d.target] = d.spelling
            mirrorAliasKeys(d.target, d.spelling, fieldTaintSet)
        end
    end
    return reps
end
-- Re-spell or drop a chainAlias entry whose SLOT dies with a break: the
-- entry describes a LIVE descendant link of the table a representative
-- inherited (`local a = t2; a.sub = q; t2 = {}` recorded "t2.sub"→"q" —
-- after the rebind that link belongs to a's spelling, round-9k).  With no
-- rep for the namespace the old table is unreachable and the entry drops.
local function respellDeadSlot(slot, reps)
    local ctx = fnEventCtx
    if not (ctx and ctx.chainAlias) then return end
    local tgt = ctx.chainAlias[slot]
    ctx.chainAlias[slot] = nil
    if not (tgt and reps) then return end
    local bestT, bestRep
    for t, rep in pairs(reps) do
        if aliasTargetMatches(slot, t) and (not bestT or #t > #bestT) then
            bestT, bestRep = t, rep
        end
    end
    if not bestT then return end
    local newSlot = bestRep .. slot:sub(#bestT + 1)
    if newSlot ~= slot and newSlot ~= tgt
        and not aliasTargetMatches(tgt, newSlot) then
        ctx.chainAlias[newSlot] = tgt
    end
end
local function invalidateAliasTargetRebind(varName, fieldTaintSet)
    local ctx = fnEventCtx
    if not ctx then return end
    invalidateMayAliasCache(ctx)
    local reps = relinkBrokenTarget(varName, varName, fieldTaintSet)
    if ctx.chainAlias then
        local dead = {}
        for slot in pairs(ctx.chainAlias) do
            if keyRootName(slot) == varName then
                dead[#dead + 1] = slot
            end
        end
        for _, slot in ipairs(dead) do
            respellDeadSlot(slot, reps)
        end
    end
    severMayAliases(varName, fieldTaintSet)
end
-- A SLOT being re-bound (`updateInfo.sub = other`) is the same break for
-- dependents whose target/canon reaches through that slot spelling
-- (round-9g/9i).  Returns the representatives map so the caller can
-- re-spell descendant entries of the dying spelling (round-9k).
local function invalidateSlotRetarget(slotKey, fieldTaintSet)
    invalidateMayAliasCache(fnEventCtx)
    local reps = relinkBrokenTarget(slotKey, nil, fieldTaintSet)
    severMayAliases(slotKey, fieldTaintSet)
    return reps
end

-- Path-scoped PROVENANCE state (round-8e, reachability-precise round-8f):
-- payloadNames, independentFields and the alias maps are snapshotted at
-- if-entry; each clause walks from that entry state; and only REACHABLE
-- exits merge — a terminating branch's provenance changes are rolled back
-- entirely (they cannot reach post-if code, so they must neither leak
-- payload classifications NOR poison aliases).  Merge rules:
--   * independentFields / aliasPoisoned: union (a mark on any surviving
--     path keeps the gate away — conservative direction);
--   * payloadNames: payload-only iff EVERY contributing path that has the
--     name TAINTED classifies it payload-only (branch exits inherit the
--     entry classification, so surviving exits subsume the entry state for
--     reachable paths);
--   * aliasCanon: exact agreement across all contributions, else POISON.
-- The entry state contributes only when a fall-through path exists (no bare
-- else).  Nested closures are unaffected (walkFunctionBody swaps the whole
-- ctx and restores it).
local function copyProvState(ctx)
    if not ctx then return nil end
    local st = { payload = {}, payloadEvents = {}, independent = {}, canon = {}, poisoned = {},
        chain = {}, may = {}, mayCleanExact = {}, mayCleanSubtree = {},
        mayEdgeVersions = {}, mayCleanEdges = {} }
    for k, v in pairs(ctx.payloadNames or {}) do st.payload[k] = v end
    for name, events in pairs(ctx.payloadEvents or {}) do
        local copy = {}
        for eventName in pairs(events) do copy[eventName] = true end
        st.payloadEvents[name] = copy
    end
    for k in pairs(ctx.independentFields or {}) do st.independent[k] = true end
    for k, v in pairs(ctx.aliasCanon or {}) do st.canon[k] = v end
    for k in pairs(ctx.aliasPoisoned or {}) do st.poisoned[k] = true end
    for k, v in pairs(ctx.chainAlias or {}) do st.chain[k] = v end
    -- May-alias links are path-state like every other flow map
    -- (round-10d follow-up): a clause that SEVERS a link must roll back
    -- when other reachable paths keep it, and an all-arms sever must
    -- stick — both fall out of the snapshot/merge below.
    for slot, tgts in pairs(ctx.chainAliasMay or {}) do
        local copy = {}
        for t in pairs(tgts) do copy[t] = true end
        st.may[slot] = copy
    end
    for key in pairs(ctx.mayAliasCleanExact or {}) do
        st.mayCleanExact[key] = true
    end
    for key in pairs(ctx.mayAliasCleanSubtree or {}) do
        st.mayCleanSubtree[key] = true
    end
    for slot, targets in pairs(ctx.mayAliasEdgeVersions or {}) do
        local copy = {}
        for target, version in pairs(targets) do
            copy[target] = version
        end
        st.mayEdgeVersions[slot] = copy
    end
    for key, slots in pairs(ctx.mayAliasCleanEdges or {}) do
        local slotCopy = {}
        for slot, targets in pairs(slots) do
            local targetCopy = {}
            for target, version in pairs(targets) do
                targetCopy[target] = version
            end
            slotCopy[slot] = targetCopy
        end
        st.mayCleanEdges[key] = slotCopy
    end
    return st
end
local function setProvState(ctx, st)
    if not (ctx and st) then return end
    local p, pe, i, c, po, ch, my = {}, {}, {}, {}, {}, {}, {}
    local cleanExact, cleanSubtree = {}, {}
    local edgeVersions, cleanEdges = {}, {}
    for k, v in pairs(st.payload) do p[k] = v end
    for name, events in pairs(st.payloadEvents or {}) do
        pe[name] = {}
        for eventName in pairs(events) do pe[name][eventName] = true end
    end
    for k in pairs(st.independent) do i[k] = true end
    for k, v in pairs(st.canon) do c[k] = v end
    for k in pairs(st.poisoned) do po[k] = true end
    for k, v in pairs(st.chain or {}) do ch[k] = v end
    for slot, tgts in pairs(st.may or {}) do
        my[slot] = {}
        for t in pairs(tgts) do my[slot][t] = true end
    end
    for key in pairs(st.mayCleanExact or {}) do cleanExact[key] = true end
    for key in pairs(st.mayCleanSubtree or {}) do cleanSubtree[key] = true end
    for slot, targets in pairs(st.mayEdgeVersions or {}) do
        local copy = {}
        for target, version in pairs(targets) do copy[target] = version end
        edgeVersions[slot] = copy
    end
    for key, slots in pairs(st.mayCleanEdges or {}) do
        local slotCopy = {}
        for slot, targets in pairs(slots) do
            local targetCopy = {}
            for target, version in pairs(targets) do
                targetCopy[target] = version
            end
            slotCopy[slot] = targetCopy
        end
        cleanEdges[key] = slotCopy
    end
    ctx.payloadNames, ctx.payloadEvents, ctx.independentFields = p, pe, i
    ctx.aliasCanon, ctx.aliasPoisoned = c, po
    ctx.chainAlias = ch
    ctx.chainAliasMay = next(my) ~= nil and my or nil
    ctx.mayAliasCleanExact = cleanExact
    ctx.mayAliasCleanSubtree = cleanSubtree
    ctx.mayAliasEdgeVersions = edgeVersions
    ctx.mayAliasCleanEdges = cleanEdges
    invalidateMayAliasCache(ctx)
end
-- contributions: array of { taint = <taint-set at exit>, prov = <prov state> }
-- Returns the chain-alias DISAGREEMENTS: { { slot = key, tgts = {t1, ...} } }
-- — slots whose linkage differs across surviving paths.  The caller decides
-- (after the field union) whether the ambiguity needs a contamination
-- marker (round-9f): the merged map keeps only exact agreements.
local function applyMergedProvState(ctx, contributions)
    local payload, payloadEvents, independent, canon, poisoned = {}, {}, {}, {}, {}
    local aliasDisagreements
    local names = {}
    for _, con in ipairs(contributions) do
        for k in pairs(con.prov.independent) do independent[k] = true end
        for k in pairs(con.prov.poisoned) do poisoned[k] = true end
        for n in pairs(con.prov.payload) do names[n] = true end
        for n in pairs(con.prov.canon) do names[n] = true end
    end
    for n in pairs(names) do
        local anyPayload, allPayloadWhereTainted = false, true
        for _, con in ipairs(contributions) do
            local isP = con.prov.payload[n]
            if isP then anyPayload = true end
            if con.taint[n] and not isP then allPayloadWhereTainted = false end
        end
        if anyPayload and allPayloadWhereTainted then
            payload[n] = true
            local events = {}
            for _, con in ipairs(contributions) do
                for eventName in pairs((con.prov.payloadEvents or {})[n] or {}) do
                    events[eventName] = true
                end
            end
            payloadEvents[n] = events
        end
        if not poisoned[n] then
            local val = contributions[1].prov.canon[n]
            local agree = true
            for _, con in ipairs(contributions) do
                if con.prov.canon[n] ~= val then
                    agree = false
                    break
                end
            end
            if not agree then
                poisoned[n] = true
                local tgts, seen = {}, {}
                for _, con in ipairs(contributions) do
                    local target = con.prov.canon[n]
                    if target and not seen[target] then
                        seen[target] = true
                        tgts[#tgts + 1] = target
                    end
                end
                aliasDisagreements = aliasDisagreements or {}
                aliasDisagreements[#aliasDisagreements + 1] = {
                    name = n,
                    tgts = tgts,
                }
            elseif val ~= nil then
                canon[n] = val
            end
        end
    end
    local chain, disagreements = {}, nil
    local slots = {}
    for _, con in ipairs(contributions) do
        for k in pairs(con.prov.chain or {}) do slots[k] = true end
    end
    for slot in pairs(slots) do
        local val = contributions[1].prov.chain and contributions[1].prov.chain[slot]
        local agree = true
        local tgts, seen = {}, {}
        for _, con in ipairs(contributions) do
            local t = con.prov.chain and con.prov.chain[slot]
            if t ~= val then agree = false end
            if t and not seen[t] then
                seen[t] = true
                tgts[#tgts + 1] = t
            end
        end
        if agree and val then
            chain[slot] = val
        elseif not agree then
            disagreements = disagreements or {}
            disagreements[#disagreements + 1] = { slot = slot, tgts = tgts }
        end
    end
    ctx.payloadNames, ctx.payloadEvents, ctx.independentFields = payload, payloadEvents, independent
    ctx.aliasCanon, ctx.aliasPoisoned = canon, poisoned
    ctx.chainAlias = chain
    -- May-alias links merge by UNION over reachable exits (round-10d
    -- follow-up): a link severed on EVERY reachable path (all-arms
    -- guaranteed replacement, repeat-body rebind — repeat contributes no
    -- entry state) stays severed; a link surviving ANY path persists
    -- (zero-iteration while/for keep it through the entry contribution).
    local may
    for _, con in ipairs(contributions) do
        for slot, tgts in pairs(con.prov.may or {}) do
            may = may or {}
            local set = may[slot]
            if not set then
                set = {}
                may[slot] = set
            end
            for t in pairs(tgts) do set[t] = true end
        end
    end
    ctx.chainAliasMay = may
    -- Epoch numbers are concrete transfer history, while the joined lattice
    -- needs only two facts per concrete key/edge: blocked or live. Normalize
    -- every surviving edge to one canonical epoch after the path-specific
    -- states have been captured. The clean-edge join below classifies each
    -- target from the ORIGINAL contribution versions, then writes the same
    -- canonical epoch as its cutoff when every path blocks it. This finite
    -- abstraction is what lets loops containing `clean; reassert` converge:
    -- each runtime iteration creates a new incarnation, but every incarnation
    -- has the same live abstract state.
    local edgeVersions = {}
    for slot, targets in pairs(may or {}) do
        local slotVersions = {}
        edgeVersions[slot] = slotVersions
        for target in pairs(targets) do
            slotVersions[target] = 1
        end
    end
    ctx.mayAliasEdgeVersions = edgeVersions
    local function intersectClean(field)
        local result = {}
        local first = contributions[1] and contributions[1].prov[field] or {}
        for key in pairs(first or {}) do
            local every = true
            for i = 2, #contributions do
                if not (contributions[i].prov[field]
                    and contributions[i].prov[field][key]) then
                    every = false
                    break
                end
            end
            if every then result[key] = true end
        end
        return result
    end
    ctx.mayAliasCleanExact = intersectClean("mayCleanExact")
    ctx.mayAliasCleanSubtree = intersectClean("mayCleanSubtree")
    -- A concrete overwrite excludes one wildcard TARGET only when every
    -- reachable path on which that target edge exists still has that edge
    -- behind its local cutoff. Target-specific joins avoid both hazards:
    -- one clean arm cannot suppress an active arm, while a later edge to a
    -- different target cannot revive an older excluded target.
    local cleanKeys = {}
    for _, con in ipairs(contributions) do
        for key in pairs(con.prov.mayCleanEdges or {}) do
            cleanKeys[key] = true
        end
    end
    local cleanEdges = {}
    for key in pairs(cleanKeys) do
        for slot, targets in pairs(may or {}) do
            for target in pairs(targets) do
                local sawEdge, blockedEvery = false, true
                for _, con in ipairs(contributions) do
                    local pathTargets = con.prov.may
                        and con.prov.may[slot]
                    if pathTargets and pathTargets[target] then
                        sawEdge = true
                        local version = con.prov.mayEdgeVersions
                            and con.prov.mayEdgeVersions[slot]
                            and con.prov.mayEdgeVersions[slot][target] or 0
                        local cutoff = con.prov.mayCleanEdges
                            and con.prov.mayCleanEdges[key]
                            and con.prov.mayCleanEdges[key][slot]
                            and con.prov.mayCleanEdges[key][slot][target]
                        if not cutoff or version > cutoff then
                            blockedEvery = false
                            break
                        end
                    end
                end
                if sawEdge and blockedEvery then
                    local slots = cleanEdges[key]
                    if not slots then
                        slots = {}
                        cleanEdges[key] = slots
                    end
                    local blockedTargets = slots[slot]
                    if not blockedTargets then
                        blockedTargets = {}
                        slots[slot] = blockedTargets
                    end
                    blockedTargets[target] =
                        edgeVersions[slot][target]
                end
            end
        end
    end
    ctx.mayAliasCleanEdges = cleanEdges
    invalidateMayAliasCache(ctx)
    return disagreements, aliasDisagreements
end

local function materializeFlowDisagreements(ctx, chainDisagreements,
        aliasDisagreements, fieldTaintSet)
    if not (ctx and (chainDisagreements or aliasDisagreements)) then return end
    local function anyTaintUnder(prefix)
        local pdot, pbr = prefix .. ".", prefix .. "["
        for key, value in pairs(fieldTaintSet) do
            if value and (key:sub(1, #pdot) == pdot
                or key:sub(1, #pbr) == pbr) then
                return true
            end
        end
        return false
    end
    local function markIfDirty(spelling, targets)
        local dirty = anyTaintUnder(spelling)
        if not dirty then
            for _, target in ipairs(targets or {}) do
                if anyTaintUnder(target) then dirty = true break end
            end
        end
        if dirty then
            local marker = spelling .. "[*]"
            fieldTaintSet[marker] = true
            ctx.independentFields = ctx.independentFields or {}
            ctx.independentFields[marker] = true
        end
        -- Round-10d: whether or not taint is in sight NOW, the dropped
        -- link is a live may-alias — a LATER write through EITHER
        -- spelling must stay visible through the other (mayAliasTainted).
        -- Symmetric by nature (two spellings may denote one table), so
        -- record both directions: a write through the poisoned name
        -- (`while X do h = c end; h.foo = S(); c.foo`) reads through the
        -- target spelling.
        if targets and #targets > 0 then
            ctx.chainAliasMay = ctx.chainAliasMay or {}
            local function link(from, to)
                if from == to then return end
                local set = ctx.chainAliasMay[from]
                if not set then
                    set = {}
                    ctx.chainAliasMay[from] = set
                end
                set[to] = true
                refreshMayAliasEdge(ctx, from, to)
            end
            for _, target in ipairs(targets) do
                link(spelling, target)
                link(target, spelling)
            end
            invalidateMayAliasCache(ctx)
        end
    end
    for _, d in ipairs(chainDisagreements or {}) do
        markIfDirty(d.slot, d.tgts)
    end
    for _, d in ipairs(aliasDisagreements or {}) do
        markIfDirty(d.name, d.tgts)
    end
end

-- (Freshly-tainted assignment targets route into the dispatch-untaint
-- buckets inline in the two-pass statement walkers: payload copies join
-- payloadNames, everything else goes independent — classified in pass 1
-- via eventTaintedOnly, applied in pass 2.)

local function copyEventSet(set)
    local r = {}
    for k in pairs(set or {}) do r[k] = true end
    return r
end

-- Event-discriminant constraint for conditions composed from canonical
-- equality/inequality tests.  Returns the secret-event sets still possible
-- when the condition is true and false, respectively; nil means unmodeled.
local function refineSecretEvents(cond, current)
    local ctx = fnEventCtx
    if not (ctx and ctx.eventName) then return nil end
    local function atom(n)
        n = stripParens(n)
        if type(n) ~= "table" then return nil end
        if n.AstType == "BinopExpr" and (n.Op == "==" or n.Op == "~=") then
            local lit = stringLiteralValue(n.Lhs) or stringLiteralValue(n.Rhs)
            local var = (isVarRef(n.Lhs) and n.Lhs) or (isVarRef(n.Rhs) and n.Rhs)
            if not (lit and var and var.Name == ctx.eventName) then return nil end
            local one = { [lit] = true }
            if n.Op == "==" then
                return "include", one, "exclude", one
            end
            return "exclude", one, "include", one
        end
        if n.AstType == "BinopExpr" and (n.Op == "or" or n.Op == "and") then
            local lt, ls, lf, lfs = atom(n.Lhs)
            local rt, rs, rf, rfs = atom(n.Rhs)
            if not (lt and rt and lf and rf) then return nil end
            local truthMode = n.Op == "or" and "include" or "exclude"
            local falseMode = n.Op == "or" and "exclude" or "include"
            if lt ~= truthMode or rt ~= truthMode
                or lf ~= falseMode or rf ~= falseMode then return nil end
            local ts, fs = copyEventSet(ls), copyEventSet(lfs)
            for k in pairs(rs) do ts[k] = true end
            for k in pairs(rfs) do fs[k] = true end
            return truthMode, ts, falseMode, fs
        end
        return nil
    end
    local tm, ts, fm, fs = atom(cond)
    if not tm then return nil end
    local function apply(mode, named)
        local r = {}
        for eventName in pairs(current or {}) do
            if (mode == "include" and named[eventName])
                or (mode == "exclude" and not named[eventName]) then
                r[eventName] = true
            end
        end
        return r
    end
    return apply(tm, ts), apply(fm, fs)
end

-- Narrow entry payload taint to the secret events possible on this dispatch
-- path.  Copies with unknown positional provenance remain conservative; the
-- original handler parameters and vararg positions are precise.
local function restrictPayloadToEvents(tset, ftset, possibleEvents)
    local ctx = fnEventCtx
    if not ctx then return nil end
    local cleared = {}
    for name, events in pairs(ctx.payloadEvents or ctx.entryPayloadEvents or {}) do
        local live = false
        for eventName in pairs(events) do
            if possibleEvents[eventName] then live = true break end
        end
        if not live and ctx.payloadNames and ctx.payloadNames[name] then
            tset[name] = nil
            cleared[name] = true
        end
    end
    for name in pairs(cleared) do
        if ctx.payloadNames then ctx.payloadNames[name] = nil end
        if ctx.payloadEvents then ctx.payloadEvents[name] = nil end
    end
    for key in pairs(ftset) do
        local root = key:match("^([%w_]+)")
        if root and cleared[root]
            and not (ctx.independentFields and ctx.independentFields[key]) then
            ftset[key] = nil
        end
    end
    local varargs = {}
    for eventName in pairs(possibleEvents) do
        for pos in pairs((ctx.eventVarargSecrets or {})[eventName] or {}) do
            varargs[pos] = true
        end
    end
    return varargs
end

-- Clear event-payload-derived (aura-class) taint: the names still carrying
-- pure event-entry taint (fnEventCtx.payloadNames — copies included, values
-- re-tainted from other sources excluded via markIndependentTaint) plus any
-- tainted fields rooted at them.  Used by the round-8 restriction-gate
-- dominance rules: a falsy aura gate proves exactly this class safe and
-- nothing else.
local function clearPayloadRootedTaint(tset, ftset)
    local ctx = fnEventCtx
    if not (ctx and ctx.payloadNames) then return end
    -- Gate-ungoverned payload (UNIT_AURA_BLOCKED.auraInstanceID is secret
    -- unconditionally): a falsy aura gate proves nothing here — clear
    -- nothing.
    if ctx.gateGoverned == false then return end
    invalidateMayAliasCache(ctx)
    local poisoned = ctx.aliasPoisoned
    for name in pairs(ctx.payloadNames) do
        -- Path-ambiguous names may hold non-payload data on some path — the
        -- gate must not erase their base taint (round-8e).
        if not (poisoned and poisoned[name]) then
            tset[name] = nil
        end
    end
    for key in pairs(ftset) do
        local root = key:match("^([%w_]+)")
        -- A field entry marked independent carries NON-payload taint (it was
        -- assigned from another source onto a payload-named table); the aura
        -- gate does not govern it, so it survives the clear (round-8b).
        -- Poisoned roots survive for the same may-alias reason (round-8e).
        if root and ctx.payloadNames[root]
            and not (poisoned and poisoned[root])
            and not (ctx.independentFields and ctx.independentFields[key]) then
            ftset[key] = nil
        end
    end
end

-- Does this if-clause condition GUARANTEE an unrestricted state when true?
-- Strict by construction: built from restrictedImpliesTrue's contrapositive
-- (`not X` true ⇒ X false ⇒ unrestricted, since restricted ⇒ X true).  An
-- `and` needs only ONE such conjunct (all conjuncts ran truthy); `or` proves
-- nothing (the other disjunct may admit a restricted state).  This is the
-- polarity gateConditionPolarity cannot give soundly — its "negative" is a
-- syntactic inversion, and `not (A and gate())` is negative-shaped yet true
-- whenever A is false, restriction state unknown.
local function condTrueImpliesUnrestricted(cond, registry)
    cond = stripParens(cond)
    if type(cond) ~= "table" then return false end
    if cond.AstType == "UnopExpr" and cond.Op == "not" then
        return restrictedImpliesTrue(cond.Rhs, registry, fnAliases) ~= nil
    end
    if cond.AstType == "BinopExpr" and cond.Op == "and" then
        return condTrueImpliesUnrestricted(cond.Lhs, registry)
            or condTrueImpliesUnrestricted(cond.Rhs, registry)
    end
    if cond.AstType == "BinopExpr" and (cond.Op == "==" or cond.Op == "~=") then
        local lhsIsLit = type(cond.Lhs) == "table" and cond.Lhs.AstType == "BooleanExpr"
        local rhsIsLit = type(cond.Rhs) == "table" and cond.Rhs.AstType == "BooleanExpr"
        local lit = (lhsIsLit and cond.Lhs) or (rhsIsLit and cond.Rhs) or nil
        if lit then
            local other = lhsIsLit and cond.Rhs or cond.Lhs
            local wantFalse = (cond.Op == "==" and lit.Value == false)
                or (cond.Op == "~=" and lit.Value == true)
            if wantFalse then
                return restrictedImpliesTrue(other, registry, fnAliases) ~= nil
            end
        end
    end
    return false
end

-- Constructor results are plain table references; taint belongs to their
-- stored entries.  Preserve that field sensitivity when a constructor is
-- assigned instead of tainting the container root (which made `{x=S()}.y`
-- and the table's own truthiness false positives).
local function constructorEntrySuffix(entry, listIndex)
    if entry.Type == "KeyString" and type(entry.Key) == "string" then
        return "." .. entry.Key, listIndex
    end
    if entry.Type == "Value" then
        return "[" .. tostring(listIndex) .. "]", listIndex + 1
    end
    local key = stripParens(entry.Key)
    if type(key) ~= "table" then return nil, listIndex end
    -- Shared literal canonicalization (round-10d): constructor bracket
    -- keys MUST spell exactly like chainRefKey's read keys or writes and
    -- reads desynchronize (`{["a\nb"] = S()}` vs `t["a\nb"]`).
    local seg = literalIndexSegment(key)
    if seg then return seg, listIndex end
    return nil, listIndex
end

local function constructorScalarTainted(expr, taintSet, fieldTaintSet, registry)
    expr = stripParens(expr)
    if type(expr) ~= "table" then return false end
    if isValueTainted(expr, taintSet, fieldTaintSet, registry) then return true end
    if expr.AstType == "CallExpr" then
        local name, kind = callTargetName(expr.Base)
        if name == "pcall" or name == "xpcall" then
            -- Scalar constructor entry receives the clean success boolean;
            -- multi-return tail expansion remains a deliberate boundary.
            return false
        end
        if name and (registry:isSource(name) or registry:isSecretReturning(name)) then
            return true
        end
        return kind == "method" and name ~= nil
            and registry:isAspectReturningMethod(getMethodNameFromQualified(name))
    end
    if expr.AstType == "BinopExpr" then
        return constructorScalarTainted(expr.Lhs, taintSet, fieldTaintSet, registry)
            or constructorScalarTainted(expr.Rhs, taintSet, fieldTaintSet, registry)
    end
    if expr.AstType == "UnopExpr" then
        return constructorScalarTainted(expr.Rhs, taintSet, fieldTaintSet, registry)
    end
    return false
end

constructorHasTaintedContent = function(ctor, taintSet, fieldTaintSet, registry)
    for _, entry in ipairs(ctor.EntryList or {}) do
        local value = stripParens(entry.Value)
        if type(value) == "table" and value.AstType == "ConstructorExpr" then
            if constructorHasTaintedContent(value, taintSet, fieldTaintSet,
                    registry) then
                return true
            end
        elseif value and constructorScalarTainted(value, taintSet,
                fieldTaintSet, registry) then
            return true
        end
    end
    return false
end

local function constructorTargetProvenance(targetNode)
    if not (fnKeyProvenance and fnOuterVarNodes and targetNode) then return nil end
    local rootNode = chainRootVarNode(targetNode)
    local id
    if rootNode then
        id = fnOuterVarNodes[rootNode]
        if id then id = effectiveBindingId(id, rootNode) end
    else
        -- Local declaration target (annotated by collectOuterVarNodes).
        id = fnOuterVarNodes[targetNode]
    end
    return id
end

-- Element-secret container bind (round-23): the bound NAME stays out of
-- taintSet — the container reference is never secret (truth-tests, `#`,
-- whole-value passes all stay clean) — but its ELEMENTS are possibly
-- secret, which is exactly the round-9d contamination-marker contract.
-- Field-for-field the marker-recording block inside recordConstructorFields:
-- fieldTaintSet marker + binding provenance + persistent export +
-- INDEPENDENT provenance (a falsy restriction gate does not prove elements
-- readable, so gate clears must never bless the marker).
local function recordElementContainerMarker(baseKey, targetNode, fieldTaintSet)
    if not baseKey then return end
    local marker = baseKey .. "[*]"
    fieldTaintSet[marker] = true
    if fnKeyProvenance then
        fnKeyProvenance[marker] = constructorTargetProvenance(targetNode)
    end
    exportPersistentKey(marker, targetNode)
    if fnEventCtx then
        fnEventCtx.independentFields = fnEventCtx.independentFields or {}
        fnEventCtx.independentFields[marker] = true
    end
end

local function recordConstructorFields(baseKey, ctor, targetNode, taintSet,
        fieldTaintSet, registry)
    local anyTaint, anyPayload = false, false
    local listIndex = 1
    local entries = ctor.EntryList or {}
    if #entries > 0 then invalidateMayAliasCache(fnEventCtx) end
    for entryIndex, entry in ipairs(entries) do
        local suffix
        suffix, listIndex = constructorEntrySuffix(entry, listIndex)
        local value = stripParens(entry.Value)
        -- Round-10d: a table-REFERENCE entry is a live alias — `local h =
        -- { cache = c }` links "h.cache" to c exactly like the assignment
        -- `h.cache = c` would (which records chainAlias); the constructor
        -- path dropped it, so a LATER secret write through `c` was
        -- invisible to `h.cache.*` reads. Recorded for tainted refs too:
        -- future writes through either spelling must stay unified. Bails
        -- on poisoned/self-extending targets like the assignment path.
        if fnEventCtx and type(value) == "table"
            and (value.AstType == "VarExpr" or value.AstType == "MemberExpr"
                or value.AstType == "IndexExpr") then
            local alias = resolveAliasBindingPre(value)
            if alias and alias.canon then
                if suffix then
                    local slot = baseKey .. suffix
                    if alias.canon ~= slot
                        and not aliasTargetMatches(alias.canon, slot) then
                        fnEventCtx.chainAlias = fnEventCtx.chainAlias or {}
                        fnEventCtx.chainAlias[slot] = alias.canon
                    end
                else
                    -- A computed constructor key is not one exact location,
                    -- but it may denote the slot read through any computed
                    -- spelling later.  Preserve the referenced table identity
                    -- as a wildcard may-alias instead of dropping it.
                    recordMayAliasPair(baseKey .. "[*]", alias.canon)
                end
            end
        end
        if type(value) == "table" and value.AstType == "ConstructorExpr" then
            if suffix then
                local dirty, payload = recordConstructorFields(baseKey .. suffix,
                    value, targetNode, taintSet, fieldTaintSet, registry)
                anyTaint = anyTaint or dirty
                anyPayload = anyPayload or payload
            else
                -- Unknown constructor key: collapse any tainted descendant
                -- to the container's contamination marker.
                local dirty = constructorHasTaintedContent(value, taintSet,
                    fieldTaintSet, registry)
                local payload = false
                if dirty then
                    local marker = baseKey .. "[*]"
                    fieldTaintSet[marker] = true
                    if fnKeyProvenance then
                        fnKeyProvenance[marker] = constructorTargetProvenance(targetNode)
                    end
                    exportPersistentKey(marker, targetNode)
                    if fnEventCtx then
                        fnEventCtx.independentFields = fnEventCtx.independentFields or {}
                        fnEventCtx.independentFields[marker] = true
                    end
                end
                anyTaint = anyTaint or dirty
                anyPayload = anyPayload or payload
            end
        elseif value and constructorScalarTainted(value, taintSet,
                fieldTaintSet, registry) then
            local key = suffix and (baseKey .. suffix) or (baseKey .. "[*]")
            fieldTaintSet[key] = true
            if fnKeyProvenance then
                fnKeyProvenance[key] = constructorTargetProvenance(targetNode)
            end
            exportPersistentKey(key, targetNode)
            local payloadOnly = eventTaintedOnly(value, taintSet,
                fieldTaintSet, registry)
            if fnEventCtx then
                fnEventCtx.independentFields = fnEventCtx.independentFields or {}
                if payloadOnly then
                    fnEventCtx.independentFields[key] = nil
                else
                    fnEventCtx.independentFields[key] = true
                end
            end
            anyTaint = true
            anyPayload = anyPayload or payloadOnly
        elseif suffix and type(value) == "table" and value.AstType == "CallExpr"
            and not (entry.Type == "Value" and entryIndex == #entries) then
            -- Round-23 (final review F1): a KEYED or NON-FINAL list entry
            -- calling an element-secret function sits in single-value
            -- context — the call truncates to result 1, which IS the
            -- container — so the entry's OWN slot binds the marker.
            -- stripParens above already unwrapped truncating parentheses;
            -- they do not suppress here (result 1 is still the container,
            -- mirroring the bare-final branch below). pcall/xpcall stay
            -- excluded: truncated to one value they yield only the clean
            -- ok boolean (pinned by the round-10/E10 non-final-pcall
            -- cases). Final LIST entries are owned by the expansion tail
            -- below (multi-return position, not single-value).
            local callName = callTargetName(value.Base)
            if callName and callName ~= "pcall" and callName ~= "xpcall"
                and isElementSecretCallName(callName, registry) then
                recordElementContainerMarker(baseKey .. suffix, targetNode,
                    fieldTaintSet)
            end
        end
        -- A final list-style pcall/xpcall expands its returns into the
        -- constructor.  Slot N is the clean success boolean; slot N+1 is
        -- the protected source's first possibly-secret result.
        if entry.Type == "Value" and entryIndex == #entries
            and type(value) == "table" and value.AstType == "CallExpr" then
            local callName = callTargetName(value.Base)
            local fnArg = value.Arguments and value.Arguments[1]
            local fnName = fnArg and callTargetName(fnArg)
            -- stripParens above hid any truncating parentheses around the
            -- entry: `{ (pcall(...)) }` yields ONLY the clean ok boolean,
            -- so the round-23 protected branch below must not expand it.
            -- (A parenthesized BARE call keeps result 1 — for an element-
            -- secret call that IS the container, so only the pcall branch
            -- needs the guard.)
            local truncated = type(entry.Value) == "table"
                and entry.Value.AstType == "Parentheses"
            if (callName == "pcall" or callName == "xpcall")
                and fnName and registry:isSource(fnName) then
                local spillKey = baseKey .. "[" .. tostring(listIndex) .. "]"
                fieldTaintSet[spillKey] = true
                if fnKeyProvenance then
                    fnKeyProvenance[spillKey] =
                        constructorTargetProvenance(targetNode)
                end
                exportPersistentKey(spillKey, targetNode)
                if fnEventCtx then
                    fnEventCtx.independentFields =
                        fnEventCtx.independentFields or {}
                    fnEventCtx.independentFields[spillKey] = true
                end
                anyTaint = true
            elseif (callName == "pcall" or callName == "xpcall")
                and not truncated
                and fnName and isElementSecretCallName(fnName, registry) then
                -- Round-23: a final protected ELEMENT-SECRET call expands
                -- its container into the slot after the ok boolean.
                -- listIndex is POST-advance here — the entry's own slot
                -- was listIndex-1 (the ok boolean), so listIndex names
                -- ok+1: the same arithmetic as spillKey above, pinned by
                -- the round-10 `{ pcall(S) }` t[1]-clean / t[2]-tainted
                -- cases. Marker only (independent provenance); the slot
                -- itself never enters the plain taint keys, and anyTaint
                -- stays false — the container reference is not secret.
                recordElementContainerMarker(
                    baseKey .. "[" .. tostring(listIndex) .. "]",
                    targetNode, fieldTaintSet)
            elseif callName ~= "pcall" and callName ~= "xpcall"
                and callName
                and isElementSecretCallName(callName, registry) then
                -- Round-23 bare final call: `{ Src(u) }` expands the
                -- container at the entry's OWN slot — listIndex-1
                -- post-advance; no ok boolean precedes it. Truncating
                -- parentheses keep result 1, which IS the container, so
                -- this branch needs no paren guard.
                recordElementContainerMarker(
                    baseKey .. "[" .. tostring(listIndex - 1) .. "]",
                    targetNode, fieldTaintSet)
            end
        end
    end
    return anyTaint, anyPayload
end

local function recordConstructorExprFields(baseKey, expr, targetNode, taintSet,
        fieldTaintSet, registry, resultIndex)
    -- Multi-return SPILL position (round-23, resultIndex >= 2): the only
    -- bind that reaches past result 1 is the protected-call spill —
    -- `local ok, auras = pcall(Src, ...)` lands the element-secret
    -- CONTAINER at result 2 (mirrors multiReturnTaint's pcall branch: the
    -- ok boolean at result 1 stays clean, and a single container-returning
    -- call has nothing at results 3+). A parenthesized RHS truncates to
    -- one value, so no spill position ever binds from it. Marker recording
    -- only — the container reference is never taintSet-tainted, and
    -- constructor semantics never apply at a spill position (a constructor
    -- RHS yields exactly one value, so its spill vars are plain nil).
    if resultIndex and resultIndex > 1 then
        if resultIndex == 2 and type(expr) == "table"
            and expr.AstType == "CallExpr" then
            local callName = callTargetName(expr.Base)
            if callName == "pcall" or callName == "xpcall" then
                local fnArg = expr.Arguments and expr.Arguments[1]
                local fnName = fnArg and callTargetName(fnArg)
                if fnName and isElementSecretCallName(fnName, registry) then
                    recordElementContainerMarker(baseKey, targetNode,
                        fieldTaintSet)
                end
            end
        end
        return false, false, false
    end
    expr = stripParens(expr)
    if type(expr) ~= "table" then return false, false, false end
    if expr.AstType == "ConstructorExpr" then
        local dirty, payload = recordConstructorFields(baseKey, expr,
            targetNode, taintSet, fieldTaintSet, registry)
        return dirty, payload, true
    end
    -- Element-secret bind site (round-23): an RHS calling a registered
    -- element-secret function (direct spelling or fnAliases value-copy)
    -- binds a readable container — record the contamination marker under
    -- the bind target's canonical key and NOTHING else (no taintSet entry,
    -- no constructor semantics: returns all-false so callers never treat
    -- the call as a constructor or reclassify the bound name). This runs
    -- from here rather than the LocalStatement/AssignmentStatement walk
    -- because walkStatements sits at Lua 5.1's 60-upvalue ceiling and
    -- already routes every bind shape (local, var-assign, keyed member
    -- write) through this helper with the stripped RHS. Only result
    -- position 1 binds the marker: spill LHS vars never reach this call.
    if expr.AstType == "CallExpr" then
        local callName = callTargetName(expr.Base)
        if callName and isElementSecretCallName(callName, registry) then
            recordElementContainerMarker(baseKey, targetNode, fieldTaintSet)
        end
        return false, false, false
    end
    if expr.AstType == "BinopExpr"
        and (expr.Op == "and" or expr.Op == "or") then
        local ld, lp, ls = recordConstructorExprFields(baseKey, expr.Lhs,
            targetNode, taintSet, fieldTaintSet, registry)
        local rd, rp, rs = recordConstructorExprFields(baseKey, expr.Rhs,
            targetNode, taintSet, fieldTaintSet, registry)
        return ld or rd, lp or rp, ls or rs
    end
    return false, false, false
end

--- Walk a statement list, updating taintSet/fieldTaintSet and emitting findings.
--- taintSet: map of varName → true for tainted variables.
--- fieldTaintSet: map of "<tableLocal>.<field>" → true for tainted fields.
--- debug: optional table; if present, records taintedAt[varName] = line.
walkStatements = function(stmts, taintSet, fieldTaintSet, findings, registry,
    filePath, debug, scopeControl)
    -- Locals are binding-scoped, while the historical taint/alias maps are
    -- spelling-keyed.  Save the binding hidden by the first `local name` in
    -- this lexical block, clear name-rooted state for the new binding, and
    -- restore it when the block exits.  Writes through aliases to other roots
    -- remain heap effects and are deliberately not rolled back.
    local blockLocalSnapshots = {}
    local function rootedAtName(key, name)
        if type(key) ~= "string" then return false end
        if key:sub(1, 1) == "~" then key = key:sub(2) end
        return key == name
            or key:sub(1, #name + 1) == name .. "."
            or key:sub(1, #name + 1) == name .. "["
    end
    local function takeRooted(set, name)
        local saved = {}
        if not set then return saved end
        for key, value in pairs(set) do
            if rootedAtName(key, name) then
                saved[key] = value
                set[key] = nil
            end
        end
        return saved
    end
    local function restoreRooted(set, name, saved)
        if not set then return end
        for key in pairs(set) do
            if rootedAtName(key, name) then set[key] = nil end
        end
        for key, value in pairs(saved or {}) do set[key] = value end
    end
    local function beginBlockLocal(name, targetNode, bindingPre)
        local ctx = fnEventCtx
        if ctx and ctx.mayAliasRelevantRoots
            and ctx.mayAliasRelevantRoots[name] then
            ctx.invalidateMayAliasCache(ctx)
        end
        if blockLocalSnapshots[name] then
            -- A later local of the same spelling shadows the earlier local
            -- until this same block ends; discard only the current binding.
            taintSet[name] = nil
            if fnEventCtx then
                fnEventCtx.aliasCanon[name] = nil
                fnEventCtx.aliasPoisoned[name] = nil
            end
            local keepsValue = bindingPre and (
                (bindingPre.alias and bindingPre.alias.canon == name)
                or (bindingPre.contentClean == false
                    and not (bindingPre.alias and bindingPre.alias.canon)))
            if not keepsValue then
                takeRooted(fieldTaintSet, name)
                takeRooted(fnEventCtx and fnEventCtx.independentFields, name)
                takeRooted(fnKeyProvenance, name)
                takeRooted(fnEventCtx
                    and fnEventCtx.mayAliasCleanEdges, name)
                takeRooted(fnEventCtx
                    and fnEventCtx.mayAliasEdgeVersions, name)
            end
            takeRooted(safeRefSet, name)
            return
        end
        local snap = {
            bindingId = fnOuterVarNodes and fnOuterVarNodes[targetNode] or nil,
            localized = bindingPre and bindingPre.alias
                and bindingPre.alias.canon == name or false,
            mayAliasHidden = bindingPre and bindingPre.contentClean == false
                and not (bindingPre.alias and bindingPre.alias.canon) or false,
            tainted = taintSet[name] == true,
            aliasCanon = ctx and ctx.aliasCanon[name] or nil,
            aliasPoisoned = ctx and ctx.aliasPoisoned[name] == true or false,
            payload = ctx and ctx.payloadNames and ctx.payloadNames[name] == true or false,
            payloadEvents = ctx and ctx.payloadEvents and ctx.payloadEvents[name] or nil,
            fields = takeRooted(fieldTaintSet, name),
            independent = takeRooted(ctx and ctx.independentFields, name),
            provenance = takeRooted(fnKeyProvenance, name),
            safe = takeRooted(safeRefSet, name),
            chain = {},
            may = {},
            mayCleanExact = takeRooted(
                ctx and ctx.mayAliasCleanExact, name),
            mayCleanSubtree = takeRooted(
                ctx and ctx.mayAliasCleanSubtree, name),
            mayCleanEdges = takeRooted(
                ctx and ctx.mayAliasCleanEdges, name),
            mayEdgeVersions = takeRooted(
                ctx and ctx.mayAliasEdgeVersions, name),
            dependentAliases = {},
            dependentSlots = {},
        }
        -- Other spellings that currently resolve through the soon-hidden
        -- binding must keep naming the OUTER table inside the block. Detach
        -- them onto their own spelling while the shadow is live, then merge
        -- their writes back and restore the exact link at block exit.
        if ctx and ctx.aliasCanon then
            for alias, target in pairs(ctx.aliasCanon) do
                if alias ~= name and aliasTargetMatches(target, name) then
                    snap.dependentAliases[alias] = target
                    mirrorAliasKeys(target, alias, fieldTaintSet)
                    ctx.aliasCanon[alias] = nil
                end
            end
        end
        if ctx and ctx.chainAlias then
            for slot, target in pairs(ctx.chainAlias) do
                if not rootedAtName(slot, name)
                    and aliasTargetMatches(target, name) then
                    snap.dependentSlots[slot] = target
                    mirrorAliasKeys(target, slot, fieldTaintSet)
                    ctx.chainAlias[slot] = nil
                end
            end
        end
        if ctx and ctx.chainAlias then
            for slot, target in pairs(ctx.chainAlias) do
                if rootedAtName(slot, name) then
                    snap.chain[slot] = target
                    ctx.chainAlias[slot] = nil
                end
            end
        end
        if ctx and ctx.chainAliasMay then
            for slot, targets in pairs(ctx.chainAliasMay) do
                if rootedAtName(slot, name) then
                    local copy = {}
                    for target in pairs(targets) do copy[target] = true end
                    snap.may[slot] = copy
                    ctx.chainAliasMay[slot] = nil
                end
            end
        end
        blockLocalSnapshots[name] = snap
        local escapeMap = ctx and ctx.bindingValueEscaped
        local bindingEscaped = snap.bindingId and escapeMap
            and escapeMap[snap.bindingId]
        if snap.bindingId then
            -- Persistent/captured-field seeds are keyed to the declaration's
            -- qualified binding ID.  They describe this new local's table,
            -- not the hidden outer spelling, so admit just those matching
            -- fields after the lexical shadow clear.
            for key, value in pairs(snap.fields) do
                local prov = snap.provenance[key]
                local matches = prov == snap.bindingId
                    or (type(prov) == "table"
                        and prov[snap.bindingId] == true)
                if matches then
                    fieldTaintSet[key] = value
                    if fnKeyProvenance then fnKeyProvenance[key] = prov end
                    if ctx and ctx.independentFields
                        and snap.independent[key] then
                        ctx.independentFields[key] = true
                    end
                end
            end
        end
        if snap.localized or snap.mayAliasHidden or bindingEscaped then
            -- `local cache = cache` creates a new lexical binding but keeps
            -- the exact outer table value.  Its field state therefore enters
            -- the new binding and mutations must flow back to the hidden
            -- outer binding when this block ends.
            for key, value in pairs(snap.fields) do fieldTaintSet[key] = value end
            if ctx and ctx.independentFields then
                for key, value in pairs(snap.independent) do
                    ctx.independentFields[key] = value
                end
            end
            if fnKeyProvenance then
                for key, value in pairs(snap.provenance) do
                    fnKeyProvenance[key] = value
                end
            end
        end
        taintSet[name] = nil
        if ctx then
            ctx.aliasCanon[name] = nil
            ctx.aliasPoisoned[name] = nil
            if ctx.payloadNames then ctx.payloadNames[name] = nil end
            if ctx.payloadEvents then ctx.payloadEvents[name] = nil end
        end
    end
    local function restoreBlockLocals()
        local ctx = fnEventCtx
        for name, snap in pairs(blockLocalSnapshots) do
            local escapeMap = ctx and ctx.bindingValueEscaped
            local escaped = snap.bindingId and escapeMap
                and escapeMap[snap.bindingId]
            local preserveCurrent = escaped or snap.localized
                or snap.mayAliasHidden
            local escapedFields = preserveCurrent
                and takeRooted(fieldTaintSet, name) or nil
            local escapedIndependent = preserveCurrent
                and takeRooted(ctx and ctx.independentFields, name) or nil
            local escapedProvenance = preserveCurrent
                and takeRooted(fnKeyProvenance, name) or nil
            taintSet[name] = snap.tainted and true or nil
            restoreRooted(fieldTaintSet, name, snap.fields)
            restoreRooted(ctx and ctx.independentFields, name, snap.independent)
            restoreRooted(fnKeyProvenance, name, snap.provenance)
            restoreRooted(safeRefSet, name, snap.safe)
            restoreRooted(ctx and ctx.mayAliasCleanExact, name,
                snap.mayCleanExact)
            restoreRooted(ctx and ctx.mayAliasCleanSubtree, name,
                snap.mayCleanSubtree)
            restoreRooted(ctx and ctx.mayAliasCleanEdges, name,
                snap.mayCleanEdges)
            restoreRooted(ctx and ctx.mayAliasEdgeVersions, name,
                snap.mayEdgeVersions)
            -- An escaped local table can outlive the lexical binding.  Keep
            -- its heap fields/provenance as a may-alias contribution while
            -- still restoring the hidden outer binding's state.
            for key, value in pairs(escapedFields or {}) do
                fieldTaintSet[key] = value
            end
            if ctx and ctx.independentFields then
                for key, value in pairs(escapedIndependent or {}) do
                    ctx.independentFields[key] = value
                end
            end
            if fnKeyProvenance then
                for key, value in pairs(escapedProvenance or {}) do
                    fnKeyProvenance[key] = value
                end
            end
            if ctx then
                for alias, target in pairs(snap.dependentAliases or {}) do
                    mirrorAliasKeys(alias, target, fieldTaintSet)
                    ctx.aliasCanon[alias] = target
                end
                for slot, target in pairs(snap.dependentSlots or {}) do
                    mirrorAliasKeys(slot, target, fieldTaintSet)
                    ctx.chainAlias[slot] = target
                end
                ctx.aliasCanon[name] = snap.aliasCanon
                ctx.aliasPoisoned[name] = snap.aliasPoisoned and true or nil
                if ctx.payloadNames then
                    ctx.payloadNames[name] = snap.payload and true or nil
                end
                if ctx.payloadEvents then
                    ctx.payloadEvents[name] = snap.payloadEvents
                end
                for slot in pairs(ctx.chainAlias or {}) do
                    if rootedAtName(slot, name) then ctx.chainAlias[slot] = nil end
                end
                for slot, target in pairs(snap.chain) do
                    ctx.chainAlias[slot] = target
                end
                if ctx.chainAliasMay then
                    for slot in pairs(ctx.chainAliasMay) do
                        if rootedAtName(slot, name) then
                            ctx.chainAliasMay[slot] = nil
                        end
                    end
                end
                for slot, targets in pairs(snap.may) do
                    ctx.chainAliasMay = ctx.chainAliasMay or {}
                    ctx.chainAliasMay[slot] = targets
                end
                ctx.invalidateMayAliasCache(ctx)
            end
        end
    end
    -- Per-block reachability (round-10d follow-ups 5+6): statements after
    -- a flow-ending statement never execute in ANY invocation — walking
    -- them mutated flow state (dead re-links, dead severs, dead break
    -- snapshots) that resurrected or dropped may-links every reachable
    -- exit agreed on. Flow ends on bodyTerminates' terminator set
    -- (return / error() / all-arms-return if / terminating do — the
    -- error-shadowing forfeit rides along) PLUS loop exits: a bare
    -- break, an all-arms-break if, a do-block ending in a break —
    -- loop-exit WRAPPERS end the block's flow exactly like a return
    -- (Codex catch #6). Dead statements are skipped outright.
    local unreachable = false
    for _, stmt in ipairs(stmts) do
        local t = stmt.AstType
        if unreachable or not t then
            -- dead code / Eof and other non-statement nodes: skip
        elseif t == "Function" then
            -- function name() ... end OR local function name() ... end. Inherit
            -- tainted upvalues, but function parameters shadow outer locals.
            -- A local function name is itself a lexical binding (and is
            -- recursively visible in its body), so hide any same-spelled
            -- outer scalar/table state before walking the closure.
            if stmt.IsLocal and stmt.Name and stmt.Name.Name then
                beginBlockLocal(stmt.Name.Name, stmt.Name,
                    { contentClean = true })
                taintSet[stmt.Name.Name] = nil
                recordAliasBinding(stmt.Name.Name, nil)
            end
            walkFunctionBody(stmt, taintSet, fieldTaintSet, findings, registry, filePath, debug)
        elseif t == "LocalStatement" then
            -- local a, b, c = expr1, expr2, expr3
            -- Each LHS variable is tainted if its corresponding RHS contains a
            -- source call or reads a tainted field. walkExpr also emits findings
            -- for any sinks in the RHS.
            -- When more LHS vars exist than RHS expressions, the last RHS may be
            -- a multi-return call (e.g. pcall/source). If it was tainted, propagate
            -- that taint to the overflow LHS vars as well.
            -- TWO-PASS (round-9d, same reason as AssignmentStatement): every
            -- RHS references the OUTER scope (`local a, b = 1, a` reads the
            -- outer `a`), so pass 1 walks/resolves all RHS against the
            -- pre-statement state before pass 2 binds any LHS name.
            local localList = stmt.LocalList or {}
            local initList  = stmt.InitList  or {}
            local pre = {}
            do
                local dotsAt = nil
                for i, varEntry in ipairs(localList) do
                    local p = {}
                    pre[i] = p
                    if varEntry.Name then
                        local rhs = initList[i]
                        if rhs and rhs.AstType == "DotsExpr" then
                            dotsAt = i
                            p.dots = true
                            p.dotsNode = rhs
                        elseif rhs then
                            dotsAt = nil
                            local strippedRhs = stripParens(rhs)
                            -- Detect pcall/xpcall(<source>, ...): the FIRST
                            -- return is always a clean boolean (success
                            -- flag), only the spilled subsequent LHS vars
                            -- carry the source's tainted result. F5d:
                            -- classified on the STRIPPED rhs (F5c twin) —
                            -- `local ok = (pcall(Src, 1))` binds the same
                            -- boolean the bare spelling does; the raw-RHS
                            -- check FP-tainted ok. p.multiExpr below stays
                            -- RAW: the Parentheses node carries the
                            -- truncation semantics multiReturnTaint
                            -- decodes for spill positions.
                            if strippedRhs.AstType == "CallExpr" then
                                local pname = callTargetName(strippedRhs.Base)
                                if pname == "pcall" or pname == "xpcall" then
                                    local fnArg = strippedRhs.Arguments
                                        and strippedRhs.Arguments[1]
                                    if fnArg then
                                        local fnName = callTargetName(fnArg)
                                        if fnName and registry:isSource(fnName) then
                                            p.pcallOfSource = true
                                        end
                                    end
                                end
                            end
                            p.hadSource = walkExprTop(rhs, taintSet, fieldTaintSet, findings, registry, filePath)
                            if type(strippedRhs) == "table"
                                and strippedRhs.AstType == "ConstructorExpr" then
                                p.constructor = strippedRhs
                            end
                            p.constructorExpr = strippedRhs
                            p.contentClean = isContentCleanExpr(rhs)
                                or p.constructor ~= nil
                            -- Also taint the local if the RHS directly reads
                            -- a tainted field, incl. and/or value flow.
                            p.tainted = p.hadSource
                                or isValueTainted(rhs, taintSet, fieldTaintSet, registry)
                            local selected = selectVarargTaint(rhs, 1)
                            p.payloadOnly = (not p.hadSource
                                and eventTaintedOnly(rhs, taintSet,
                                    fieldTaintSet, registry)) or selected == true
                            p.payloadEvents = payloadEventsForExpr(rhs)
                                or payloadEventsForSelect(rhs, 1)
                            p.alias = resolveAliasBindingPre(rhs)
                            p.multiExpr, p.multiIndex = rhs, 1
                        elseif dotsAt then
                            p.dotsOverflow = dotsAt
                            p.dotsNode = pre[dotsAt].dotsNode
                        elseif i > 1 and pre[i - 1] and not pre[i - 1].dots
                            and not pre[i - 1].dotsOverflow then
                            -- Spill from the last multi-return expression.
                            local prev = pre[i - 1]
                            p.multiExpr = prev.multiExpr or initList[i - 1]
                            p.multiIndex = (prev.multiIndex or 1) + 1
                            local selected = selectVarargTaint(p.multiExpr, p.multiIndex)
                            local positional = multiReturnTaint(p.multiExpr,
                                p.multiIndex, registry)
                            p.spillTainted = positional
                            if p.spillTainted == nil then p.spillTainted = prev.tainted end
                            p.spillPayloadOnly = selected == true
                            p.spillPayloadEvents = payloadEventsForSelect(
                                p.multiExpr, p.multiIndex)
                            p.spillNode = prev.spillNode or initList[i - 1]
                        end
                    end
                end
            end
            for i, varEntry in ipairs(localList) do
                local varName = varEntry.Name
                if varName then
                    local rhs = initList[i]
                    local p = pre[i]
                    beginBlockLocal(varName, varEntry, p)
                    invalidateSafeRoot(varName)
                    if p.dots then
                        -- Vararg spill (`local unit, info = ...`) inside a
                        -- detected secret-event handler whose configured
                        -- payload positions land in `...`: LHS k maps to
                        -- relative vararg index k - <dots position> + 1.
                        -- Suppressed inside dispatch branches proven to
                        -- handle a different, non-secret event.
                        local vsecret = fnEventCtx and not fnEventCtx.suppressSpill
                            and fnEventCtx.varargSecret
                        if vsecret and vsecret[1] then
                            taintSet[varName] = true
                            markPayloadTaint(varName, payloadEventsForVararg(1))
                            if debug then debug.taintedAt[varName] = nodeLine(p.dotsNode) end
                        else
                            taintSet[varName] = nil
                        end
                        recordAliasBinding(varName, nil)
                    elseif rhs then
                        if p.pcallOfSource then
                            -- LHS[i] of a pcall(<source>, ...) is the ok bool —
                            -- never tainted. But subsequent LHS vars (the spilled
                            -- result(s)) inherit the taint via the spill rule.
                            taintSet[varName] = nil
                            recordAliasBinding(varName, nil)
                        elseif p.tainted then
                            taintSet[varName] = true
                            -- classifyAssignedTaint from the pass-1 snapshot
                            if p.payloadOnly then
                                markPayloadTaint(varName, p.payloadEvents)
                            else
                                markIndependentTaint(varName)
                            end
                            applyAliasBindingPre(varName, p.alias)
                            if debug then
                                debug.taintedAt[varName] = nodeLine(rhs)
                            end
                        else
                            taintSet[varName] = nil
                            -- Alias identity is about the TABLE, not its
                            -- taint (round-9c): an UNTAINTED bare copy
                            -- (`local info = updateInfo` after a gate bail)
                            -- still names the same table, and an untracked
                            -- write through it must re-taint the canonical
                            -- root. resolveAliasBindingPre ignores
                            -- non-VarExpr shapes, so this only records
                            -- genuine copies.
                            applyAliasBindingPre(varName, p.alias)
                        end
                        if p.constructorExpr then
                            local _, hasPayload, sawConstructor =
                                recordConstructorExprFields(varName,
                                p.constructorExpr, varEntry, taintSet,
                                fieldTaintSet, registry)
                            if sawConstructor and hasPayload then
                                markPayloadTaint(varName, p.payloadEvents)
                            end
                        end
                    elseif p.dotsOverflow then
                        -- Overflow LHS var fed by a `...` spill: taint per the
                        -- handler's relative secret vararg positions (same
                        -- dispatch-branch suppression as above).
                        local vsecret = fnEventCtx and not fnEventCtx.suppressSpill
                            and fnEventCtx.varargSecret
                        if vsecret and vsecret[i - p.dotsOverflow + 1] then
                            taintSet[varName] = true
                            markPayloadTaint(varName,
                                payloadEventsForVararg(i - p.dotsOverflow + 1))
                            if debug then debug.taintedAt[varName] = nodeLine(p.dotsNode) end
                        else
                            taintSet[varName] = nil
                        end
                        recordAliasBinding(varName, nil)
                    elseif p.spillTainted then
                        -- No corresponding RHS: spill from the last multi-return expression.
                        taintSet[varName] = true
                        if p.spillPayloadOnly then
                            markPayloadTaint(varName, p.spillPayloadEvents)
                        else
                            markIndependentTaint(varName)
                        end
                        recordAliasBinding(varName, nil)
                        if debug and p.spillNode then
                            debug.taintedAt[varName] = nodeLine(p.spillNode)
                        end
                    else
                        taintSet[varName] = nil
                        recordAliasBinding(varName, nil)
                    end
                    -- Round-23 protected-call spill: `local ok, auras =
                    -- pcall(Src, ...)` lands the element-secret CONTAINER
                    -- at result 2 — a spill position the rhs bind site
                    -- above never sees. Routed through the shared helper
                    -- (upvalue-neutral: this walker sits at Lua 5.1's
                    -- 60-upvalue ceiling); resultIndex confines recording
                    -- to the exact pcall/xpcall-of-element shape at
                    -- result 2, so every other spill stays untouched.
                    if not rhs and p.multiExpr and p.multiIndex then
                        recordConstructorExprFields(varName, p.multiExpr,
                            varEntry, taintSet, fieldTaintSet, registry,
                            p.multiIndex)
                    end
                end
            end
            -- Extra RHS expressions beyond the LHS count are still evaluated
            -- (then discarded) — walk them for sinks/probe-order too.
            for i = #localList + 1, #initList do
                walkExprTop(initList[i], taintSet, fieldTaintSet, findings, registry, filePath)
            end
        elseif t == "AssignmentStatement" then
            -- a, b = expr1, expr2
            -- Also handles t.k = expr (MemberExpr LHS with "." indexer) and a
            -- `...` spill (`unit, info = ...`) inside a detected secret-event
            -- handler — round-6b: the spill was modeled only for
            -- LocalStatement, so plain assignments were a false negative.
            -- TWO-PASS (round-9d, Lua simultaneous-assignment semantics):
            -- every RHS evaluates before ANY LHS binds (`info, other =
            -- other, info` swaps), so pass 1 walks/resolves every RHS —
            -- taint, payload classification, alias identity, and the
            -- member-LHS chain keys — against the PRE-statement state, and
            -- pass 2 applies the bindings from those snapshots.
            local lhsList = stmt.Lhs or {}
            local rhsList = stmt.Rhs or {}
            if fnEventCtx then
                fnEventCtx.invalidateMayAliasCache(fnEventCtx)
            end
            local pre = {}
            do
                local dotsAt = nil
                for i, lhsExpr in ipairs(lhsList) do
                    local rhs = rhsList[i]
                    local p = {}
                    pre[i] = p
                    local isVarLhs = lhsExpr.AstType == "VarExpr" and lhsExpr.Name
                    if lhsExpr.AstType == "IndexExpr" then
                        -- The base is an address expression, not a value sink;
                        -- still walk computed bases for nested sinks/sources.
                        walkExprTop(lhsExpr.Base, taintSet, fieldTaintSet,
                            findings, registry, filePath)
                        local keyHadSource = walkExprTop(lhsExpr.Index, taintSet,
                            fieldTaintSet, findings, registry, filePath)
                        if keyHadSource or isValueTainted(lhsExpr.Index, taintSet,
                            fieldTaintSet, registry) then
                            emit(findings, filePath, nodeLine(lhsExpr.Index), 1,
                                "<index>", "<tainted-local>",
                                "tainted value used as an assignment table index")
                        end
                    elseif lhsExpr.AstType == "MemberExpr" then
                        walkExprTop(lhsExpr.Base, taintSet, fieldTaintSet,
                            findings, registry, filePath)
                    end
                    if rhs and rhs.AstType == "DotsExpr" and isVarLhs then
                        dotsAt = i
                        p.dots = true
                        p.dotsNode = rhs
                    elseif rhs then
                        dotsAt = nil
                        local strippedRhs = stripParens(rhs)
                        -- F5c: classify pcall on the STRIPPED rhs, like
                        -- the sibling constructor classifications below —
                        -- `x = (pcall(F))` assigns the SAME ok boolean
                        -- the bare spelling does (parentheses truncate to
                        -- result 1, which for pcall IS the boolean), so
                        -- the spelling must not change the verdict (the
                        -- raw-RHS check was a verified stale-marker FP on
                        -- member slots, and made the assignment spelling
                        -- `ok = (pcall(Src, 1))` taint the ok boolean).
                        -- The LocalStatement classification twin got the
                        -- same treatment (F5d).
                        if strippedRhs.AstType == "CallExpr" then
                            local pname = callTargetName(strippedRhs.Base)
                            if pname == "pcall" or pname == "xpcall" then
                                -- Round-23 F5b: result 1 of pcall/xpcall
                                -- is ALWAYS a boolean, whatever the callee
                                -- — a member slot receiving it directly is
                                -- provably content-clean (stale-marker
                                -- strong update, E38).
                                p.pcallCall = true
                                local fnArg = strippedRhs.Arguments
                                    and strippedRhs.Arguments[1]
                                local fnName = fnArg and callTargetName(fnArg)
                                if fnName and registry:isSource(fnName) then
                                    p.pcallOfSource = true
                                end
                            end
                        end
                        p.hadSource = walkExprTop(rhs, taintSet, fieldTaintSet, findings, registry, filePath)
                        if type(strippedRhs) == "table"
                            and strippedRhs.AstType == "ConstructorExpr" then
                            p.constructor = strippedRhs
                        end
                        p.constructorExpr = strippedRhs
                        -- Also taint when RHS reads a tainted local or field
                        -- (e.g. chargeInfo = result), incl. and/or value flow.
                        p.tainted = p.hadSource
                            or isValueTainted(rhs, taintSet, fieldTaintSet, registry)
                        local selected = selectVarargTaint(rhs, 1)
                        p.payloadOnly = (not p.hadSource
                            and eventTaintedOnly(rhs, taintSet,
                                fieldTaintSet, registry)) or selected == true
                        p.payloadEvents = payloadEventsForExpr(rhs)
                            or payloadEventsForSelect(rhs, 1)
                        p.alias = resolveAliasBindingPre(rhs)
                        p.multiExpr, p.multiIndex = rhs, 1
                        if lhsExpr.AstType == "MemberExpr"
                            or lhsExpr.AstType == "IndexExpr" then
                            local rawKey, volatile = chainRefKey(lhsExpr)
                            if rawKey and not volatile then
                                p.key = canonChainKey(rawKey)
                                p.contentClean = isContentCleanExpr(rhs)
                                    or p.constructor ~= nil
                                    or p.pcallCall == true
                            else
                                local prefix, segs = stableChainPrefix(lhsExpr)
                                p.prefix = prefix
                                if prefix then
                                    local slot = prefix
                                    for _, seg in ipairs(segs or {}) do
                                        slot = slot .. (seg == "*" and "[*]" or seg)
                                    end
                                    p.wildAliasSlot = slot
                                end
                                p.rawRoot = chainRootName(lhsExpr)
                                p.canonRoot = p.rawRoot and canonFieldBase(p.rawRoot)
                            end
                        end
                    elseif dotsAt and isVarLhs then
                        p.dotsOverflow = dotsAt
                        p.dotsNode = pre[dotsAt].dotsNode
                    elseif isVarLhs and #rhsList > 0 and i > #rhsList then
                        local origin = pre[#rhsList]
                        p.multiExpr = rhsList[#rhsList]
                        p.multiIndex = i - #rhsList + 1
                        local selected = selectVarargTaint(p.multiExpr, p.multiIndex)
                        local positional = multiReturnTaint(p.multiExpr,
                            p.multiIndex, registry)
                        p.spillTainted = positional
                        if p.spillTainted == nil then
                            p.spillTainted = origin and origin.tainted or false
                        end
                        p.spillPayloadOnly = selected == true
                        p.spillPayloadEvents = payloadEventsForSelect(
                            p.multiExpr, p.multiIndex)
                        p.spillNode = p.multiExpr
                    elseif (lhsExpr.AstType == "MemberExpr"
                        or lhsExpr.AstType == "IndexExpr")
                        and #rhsList > 0 and i > #rhsList then
                        -- Round-23 (final review F5/F5b): multi-return
                        -- spill into a MEMBER/INDEX target. The var-LHS
                        -- spill branch above never covered these, so
                        -- `ok, state.auras = pcall(ElementSrc, ...)` bound
                        -- the container with NO marker (verified FN); the
                        -- F5 first cut then recorded the marker but
                        -- BYPASSED the member-write lifecycle (Codex:
                        -- alias-retarget FN + stale-marker FP). Classify
                        -- the spill exactly like the var-spill branch
                        -- (positional taint, origin fallback, payload
                        -- selection) so pass 2 can run the FULL direct-
                        -- write lifecycle; multiReturnTaint's spill kind
                        -- drives the strong update ("nil"/"boolean" =
                        -- provably clean scalar lands, "element" = fresh
                        -- container: clear-then-record-marker).
                        local origin = pre[#rhsList]
                        p.multiExpr = rhsList[#rhsList]
                        p.multiIndex = i - #rhsList + 1
                        local selected = selectVarargTaint(p.multiExpr,
                            p.multiIndex)
                        local positional, spillKind = multiReturnTaint(
                            p.multiExpr, p.multiIndex, registry)
                        p.tainted = positional
                        if p.tainted == nil then
                            p.tainted = origin and origin.tainted or false
                        end
                        p.payloadOnly = selected == true
                        p.payloadEvents = payloadEventsForSelect(
                            p.multiExpr, p.multiIndex)
                        p.contentClean = spillKind ~= nil
                        local rawKey, volatile = chainRefKey(lhsExpr)
                        if rawKey and not volatile then
                            p.key = canonChainKey(rawKey)
                        else
                            -- Volatile/unkeyable chain: mirror the
                            -- direct-write keyless convention (round-9b)
                            -- — a TAINTED spill contaminates the deepest
                            -- stable prefix; clean/unknown spills record
                            -- nothing.
                            local prefix, segs = stableChainPrefix(lhsExpr)
                            p.prefix = prefix
                            if prefix then
                                local slot = prefix
                                for _, seg in ipairs(segs or {}) do
                                    slot = slot .. (seg == "*" and "[*]" or seg)
                                end
                                p.wildAliasSlot = slot
                            end
                            p.rawRoot = chainRootName(lhsExpr)
                            p.canonRoot = p.rawRoot and canonFieldBase(p.rawRoot)
                        end
                    end
                end
            end
            -- Lua evaluates every RHS and every LHS address before committing
            -- any write.  Preserve the identities named by rebound roots in a
            -- statement-local canonical namespace so pass-2 invalidation of an
            -- earlier LHS cannot mutate a later LHS's pre-assignment object.
            -- This covers root swaps/rotations and mixed root+field writes
            -- (`x, x.foo = {}, S()` writes old-x.foo).
            if #lhsList > 1 and fnEventCtx then
                local rebound = {}
                local txnSerial = stmt._quiTaintTxnSerial
                if not txnSerial then
                    local allocator = fnEventCtx.txnAllocator
                        or { serial = 0 }
                    fnEventCtx.txnAllocator = allocator
                    allocator.serial = allocator.serial + 1
                    txnSerial = allocator.serial
                    stmt._quiTaintTxnSerial = txnSerial
                end
                for _, lhsExpr in ipairs(lhsList) do
                    if lhsExpr.AstType == "VarExpr" and lhsExpr.Name then
                        -- NUL cannot occur in a Lua identifier. Keep
                        -- pre-assignment object identities in this internal
                        -- namespace so a user local can never collide with a
                        -- transaction root and inherit its field taint.
                        rebound[lhsExpr.Name] = "\0QUI_TAINT_TXN:"
                            .. tostring(txnSerial) .. ":"
                            .. lhsExpr.Name
                    end
                end
                if next(rebound) then
                    local function remapKey(key)
                        if type(key) ~= "string" then return key end
                        local volatile = key:sub(1, 1) == "~"
                        local plain = volatile and key:sub(2) or key
                        local root, rest = plain:match("^([%a_][%w_]*)(.*)$")
                        local mapped = root and rebound[root]
                        if not mapped then return key end
                        return (volatile and "~" or "") .. mapped .. rest
                    end
                    local function remapSet(set)
                        if not set then return end
                        local copy = {}
                        for key, value in pairs(set) do
                            copy[remapKey(key)] = value
                        end
                        for key in pairs(set) do set[key] = nil end
                        for key, value in pairs(copy) do set[key] = value end
                    end
                    local function remapAliasMap(map)
                        if not map then return end
                        local copy = {}
                        for name, target in pairs(map) do
                            if not rebound[name] then
                                copy[name] = remapKey(target)
                            end
                        end
                        for name in pairs(map) do map[name] = nil end
                        for name, target in pairs(copy) do map[name] = target end
                    end
                    local function remapChainMap(map)
                        if not map then return end
                        local copy = {}
                        for slot, target in pairs(map) do
                            copy[remapKey(slot)] = remapKey(target)
                        end
                        for slot in pairs(map) do map[slot] = nil end
                        for slot, target in pairs(copy) do map[slot] = target end
                    end
                    local function remapMayMap(map)
                        if not map then return nil end
                        local copy = {}
                        for slot, targets in pairs(map) do
                            local newSlot = remapKey(slot)
                            local set = copy[newSlot] or {}
                            copy[newSlot] = set
                            for target in pairs(targets) do
                                set[remapKey(target)] = true
                            end
                        end
                        return copy
                    end
                    local function remapVersionMap(map)
                        if not map then return nil end
                        local copy = {}
                        for slot, targets in pairs(map) do
                            local newSlot = remapKey(slot)
                            local versions = copy[newSlot] or {}
                            copy[newSlot] = versions
                            for target, version in pairs(targets) do
                                local newTarget = remapKey(target)
                                if version > (versions[newTarget] or 0) then
                                    versions[newTarget] = version
                                end
                            end
                        end
                        return copy
                    end
                    local function remapCleanEdgeMap(map)
                        if not map then return nil end
                        local copy = {}
                        for key, slots in pairs(map) do
                            local newKey = remapKey(key)
                            local newSlots = copy[newKey] or {}
                            copy[newKey] = newSlots
                            for slot, targets in pairs(slots) do
                                local newSlot = remapKey(slot)
                                local cutoffs = newSlots[newSlot] or {}
                                newSlots[newSlot] = cutoffs
                                for target, version in pairs(targets) do
                                    local newTarget = remapKey(target)
                                    if version > (cutoffs[newTarget] or 0) then
                                        cutoffs[newTarget] = version
                                    end
                                end
                            end
                        end
                        return copy
                    end

                    remapSet(fieldTaintSet)
                    remapSet(fnEventCtx.independentFields)
                    remapSet(fnKeyProvenance)
                    remapSet(safeRefSet)
                    remapSet(fnEventCtx.mayAliasCleanExact)
                    remapSet(fnEventCtx.mayAliasCleanSubtree)
                    remapAliasMap(fnEventCtx.aliasCanon)
                    remapChainMap(fnEventCtx.chainAlias)
                    fnEventCtx.chainAliasMay =
                        remapMayMap(fnEventCtx.chainAliasMay)
                    fnEventCtx.mayAliasEdgeVersions =
                        remapVersionMap(fnEventCtx.mayAliasEdgeVersions)
                    fnEventCtx.mayAliasCleanEdges =
                        remapCleanEdgeMap(fnEventCtx.mayAliasCleanEdges)
                    if fnEventCtx.aliasPoisoned then
                        for name in pairs(rebound) do
                            fnEventCtx.aliasPoisoned[name] = nil
                        end
                    end
                    for _, p in ipairs(pre) do
                        if p.alias and p.alias.canon then
                            p.alias.canon = remapKey(p.alias.canon)
                        end
                        p.key = remapKey(p.key)
                        p.prefix = remapKey(p.prefix)
                        p.wildAliasSlot = remapKey(p.wildAliasSlot)
                    end
                end
            end
            for i, lhsExpr in ipairs(lhsList) do
                local rhs = rhsList[i]
                local p = pre[i]
                if lhsExpr.AstType == "VarExpr" and lhsExpr.Name then
                    local varName = lhsExpr.Name
                    invalidateSafeRoot(varName)
                    invalidateAliasTargetRebind(varName, fieldTaintSet)
                    -- Round-10d: a definite rebind replaces the table this
                    -- name denotes. Survivor evidence was mirrored above
                    -- (relinkBrokenTarget); keys still spelled under the
                    -- rebound name now describe the NEW table — stale
                    -- descendant taint is a false positive (`c.foo = S();
                    -- c = {}; return c.foo or D` flagged clean code).
                    -- Sweep only when the new content is PROVEN clean or
                    -- re-recorded (empty/literal rhs, constructor — its
                    -- fields re-record below — or a bare unpoisoned copy,
                    -- whose live aliasCanon supplies the keys); unknown
                    -- rhs (calls) keeps the old keys (keep-the-taint).
                    -- Conditional/zero-iteration paths stay conservative via
                    -- their explicit state joins.  The transfer itself must
                    -- perform the strong update so guaranteed repeat paths
                    -- and post-rebind breaks can discard the old object.
                    if rhs and fnEventCtx
                        and (p.constructor
                            or isContentCleanExpr(rhs)
                            or (p.alias and p.alias.canon
                                and p.alias.canon ~= varName)) then
                        local kdot, kbr = varName .. ".", varName .. "["
                        local function rootedAtRebound(k)
                            if k:sub(1, 1) == "~" then k = k:sub(2) end
                            return k:sub(1, #kdot) == kdot
                                or k:sub(1, #kbr) == kbr
                        end
                        local dead
                        for k in pairs(fieldTaintSet) do
                            if rootedAtRebound(k) then
                                dead = dead or {}
                                dead[#dead + 1] = k
                            end
                        end
                        for _, k in ipairs(dead or {}) do
                            fieldTaintSet[k] = nil
                        end
                        if fnEventCtx and fnEventCtx.independentFields then
                            dead = nil
                            for k in pairs(fnEventCtx.independentFields) do
                                if rootedAtRebound(k) then
                                    dead = dead or {}
                                    dead[#dead + 1] = k
                                end
                            end
                            for _, k in ipairs(dead or {}) do
                                fnEventCtx.independentFields[k] = nil
                            end
                        end
                    end
                    if p.dots then
                        local vsecret = fnEventCtx and not fnEventCtx.suppressSpill
                            and fnEventCtx.varargSecret
                        if vsecret and vsecret[1] then
                            taintSet[varName] = true
                            markPayloadTaint(varName, payloadEventsForVararg(1))
                            if debug then debug.taintedAt[varName] = nodeLine(p.dotsNode) end
                        else
                            taintSet[varName] = nil
                        end
                        recordAliasBinding(varName, nil)
                    elseif rhs then
                        if p.pcallOfSource then
                            taintSet[varName] = nil
                            recordAliasBinding(varName, nil)
                        elseif p.tainted then
                            taintSet[varName] = true
                            -- classifyAssignedTaint from the pass-1 snapshot
                            if p.payloadOnly then
                                markPayloadTaint(varName, p.payloadEvents)
                            else
                                markIndependentTaint(varName)
                            end
                            applyAliasBindingPre(varName, p.alias)
                            if debug then
                                debug.taintedAt[varName] = nodeLine(rhs)
                            end
                        else
                            taintSet[varName] = nil
                            -- Untainted bare copies still record the table
                            -- alias (round-9c — see the LocalStatement twin).
                            applyAliasBindingPre(varName, p.alias)
                        end
                        if p.constructorExpr then
                            local _, hasPayload, sawConstructor =
                                recordConstructorExprFields(varName,
                                p.constructorExpr, lhsExpr, taintSet,
                                fieldTaintSet, registry)
                            if sawConstructor then
                                markIndependentTaint(varName)
                                if hasPayload then
                                    markPayloadTaint(varName, p.payloadEvents)
                                end
                            end
                        end
                    elseif p.dotsOverflow then
                        -- Overflow LHS var fed by the `...` spill.
                        local vsecret = fnEventCtx and not fnEventCtx.suppressSpill
                            and fnEventCtx.varargSecret
                        if vsecret and vsecret[i - p.dotsOverflow + 1] then
                            taintSet[varName] = true
                            markPayloadTaint(varName,
                                payloadEventsForVararg(i - p.dotsOverflow + 1))
                            if debug then debug.taintedAt[varName] = nodeLine(p.dotsNode) end
                        else
                            taintSet[varName] = nil
                        end
                        recordAliasBinding(varName, nil)
                    elseif p.spillTainted then
                        taintSet[varName] = true
                        if p.spillPayloadOnly then
                            markPayloadTaint(varName, p.spillPayloadEvents)
                        else
                            markIndependentTaint(varName)
                        end
                        recordAliasBinding(varName, nil)
                        if debug and p.spillNode then
                            debug.taintedAt[varName] = nodeLine(p.spillNode)
                        end
                    else
                        -- Missing/non-multi-return RHS assigns nil and must
                        -- clear any taint left on the old variable binding.
                        taintSet[varName] = nil
                        recordAliasBinding(varName, nil)
                    end
                    -- Round-23 protected-call spill (twin of the
                    -- LocalStatement site — round-6b taught that modeling
                    -- spills only for locals leaves plain assignments as
                    -- false negatives). Marker-only recording via the
                    -- shared helper; resultIndex gates the shape.
                    if not rhs and p.multiExpr and p.multiIndex then
                        recordConstructorExprFields(varName, p.multiExpr,
                            lhsExpr, taintSet, fieldTaintSet, registry,
                            p.multiIndex)
                    end
                elseif lhsExpr.AstType == "MemberExpr"
                    or lhsExpr.AstType == "IndexExpr" then
                    -- Alias-canonical key (round-8d, resolved in pass 1):
                    -- writes through `local info = updateInfo` land on
                    -- updateInfo's key.  Deep dotted AND stable-bracketed
                    -- chains key on the FULL canonical chain (round-9/9b:
                    -- `updateInfo.sub.cd = X()` and `updateInfo.sub[1] =
                    -- X()` previously fell through key-less, losing the
                    -- independent provenance that keeps the write out of
                    -- aura-gate clears — the gate then laundered the
                    -- cooldown secret).  Volatile keys (a variable bracket
                    -- index in the chain) have no sound identity — see the
                    -- keyless fallback below.
                    if p.key then
                        -- F5b: member/index SPILL writes (no rhs; pass-1
                        -- snapshot carries multiExpr/multiIndex) run the
                        -- SAME lifecycle as a direct assignment, in the
                        -- same order — safe-key invalidation, slot
                        -- retarget + chainAlias drop + descendant
                        -- respell, provenance re-record, tainted set /
                        -- content-clean strong update — parity is the
                        -- contract (a spill IS a write to the slot).
                        if rhs or (p.multiExpr and p.multiIndex) then
                            invalidateSafeKey(p.key)
                            -- ANY write to the slot re-binds what the chain
                            -- denotes: existing chain aliases for the slot
                            -- and its descendants drop (round-9f); a bare
                            -- unpoisoned VARIABLE rhs then records a LIVE
                            -- alias — later mutations through EITHER
                            -- spelling stay unified via canonChainKey (a
                            -- one-shot snapshot desynchronized).
                            if fnEventCtx and fnEventCtx.chainAlias then
                                -- Dependents whose alias reaches THROUGH
                                -- this slot dangle now — snapshot their
                                -- keys before anything drops (round-9g).
                                local reps = invalidateSlotRetarget(p.key, fieldTaintSet)
                                fnEventCtx.chainAlias[p.key] = nil
                                -- Descendant entries spelled through the
                                -- dying slot describe LIVE links of the
                                -- table a representative inherited —
                                -- re-spell them under the rep instead of
                                -- dropping (round-9k).
                                local kdot, kbr = p.key .. ".", p.key .. "["
                                local dead
                                for slot in pairs(fnEventCtx.chainAlias) do
                                    if slot:sub(1, #kdot) == kdot
                                        or slot:sub(1, #kbr) == kbr then
                                        dead = dead or {}
                                        dead[#dead + 1] = slot
                                    end
                                end
                                for _, slot in ipairs(dead or {}) do
                                    respellDeadSlot(slot, reps)
                                end
                                if p.alias and p.alias.canon
                                    and p.alias.canon ~= p.key then
                                    if not aliasTargetMatches(p.alias.canon, p.key) then
                                        -- Same-root DISJOINT subtrees are
                                        -- legitimate aliases too
                                        -- (`updateInfo.sub =
                                        -- updateInfo.other`, round-9h) —
                                        -- only a target EXTENDING the slot
                                        -- is unrepresentable.
                                        fnEventCtx.chainAlias[p.key] = p.alias.canon
                                        p.aliasRecorded = true
                                    else
                                        -- Self-nesting hoist (`t.sub =
                                        -- t.sub.inner`): a live link would
                                        -- rewrite unboundedly — snapshot
                                        -- the target's keys into the slot
                                        -- spelling instead; old direct
                                        -- keys stale-keep (conservative).
                                        mirrorAliasKeys(p.alias.canon, p.key, fieldTaintSet)
                                    end
                                end
                            end
                            -- A REAL write (either polarity) re-records the
                            -- key's BINDING provenance (round-10c, Codex
                            -- catch #3: plain retirement made taint
                            -- name-global again — an outer write then a
                            -- shadow read consumed the outer cache's
                            -- taint). Alias-rewritten keys (lexical root ≠
                            -- key root) clear to legacy always-usable.
                            if fnKeyProvenance then
                                local provRoot = p.key:match("^([%a_][%w_]*)")
                                local provNode = chainRootVarNode(lhsExpr)
                                local provId
                                if provNode and provNode.Name == provRoot then
                                    provId = fnOuterVarNodes
                                        and fnOuterVarNodes[provNode] or nil
                                    -- Captured-upvalue writes carry the
                                    -- ancestor binding's qualified ID —
                                    -- ancestry identity, never a shared
                                    -- class (#8c/#10).
                                    provId = provId
                                        and effectiveBindingId(provId, provNode)
                                end
                                -- Escape/privacy is resolved at READ time
                                -- (bindingEvidenceUsable) — recording nil
                                -- here leaked escaped-write taint into
                                -- unrelated fresh shadows (Codex catch #4).
                                fnKeyProvenance[p.key] = provId
                            end
                            if p.tainted then
                                fieldTaintSet[p.key] = true
                                exportPersistentKey(p.key, lhsExpr)
                                -- Field provenance (round-8b): a field whose
                                -- taint came from anything OTHER than a pure
                                -- payload copy is independent — the aura-gate
                                -- clear and the gate-wildcard proof must not
                                -- bless it just because its ROOT is a payload
                                -- name (`updateInfo.cd = C_Spell.X(...)`).
                                if fnEventCtx then
                                    fnEventCtx.independentFields = fnEventCtx.independentFields or {}
                                    if p.payloadOnly and not p.hadSource then
                                        fnEventCtx.independentFields[p.key] = nil
                                    else
                                        fnEventCtx.independentFields[p.key] = true
                                    end
                                end
                            else
                                fieldTaintSet[p.key] = nil
                                if fnEventCtx and fnEventCtx.independentFields then
                                    fnEventCtx.independentFields[p.key] = nil
                                end
                                -- A replacement of a parent slot orphans
                                -- every recorded descendant — `t.sub = {}`
                                -- after `t.sub.cd = Source()` must clear
                                -- "t.sub.cd" and any "t.sub[*]" contamination
                                -- (round-9d FP fix).  Three shapes
                                -- (round-9e/9f):
                                --   * provably-empty rhs (empty ctor,
                                --     scalar literal): sweep only;
                                --   * bare unpoisoned VARIABLE rhs: sweep
                                --     the old slot-spelled keys — the LIVE
                                --     chainAlias recorded above unifies all
                                --     later reads/writes with the source's
                                --     keys (no snapshot to desynchronize);
                                --   * anything else (calls, non-empty
                                --     ctors, poisoned names): unknown
                                --     content — keep the old keys
                                --     (conservative, keep-the-taint).
                                if p.contentClean or p.aliasRecorded then
                                    local kdot, kbr = p.key .. ".", p.key .. "["
                                    for k in pairs(fieldTaintSet) do
                                        if k:sub(1, #kdot) == kdot or k:sub(1, #kbr) == kbr then
                                            fieldTaintSet[k] = nil
                                        end
                                    end
                                    if fnEventCtx and fnEventCtx.independentFields then
                                        for k in pairs(fnEventCtx.independentFields) do
                                            if k:sub(1, #kdot) == kdot or k:sub(1, #kbr) == kbr then
                                                fnEventCtx.independentFields[k] = nil
                                            end
                                        end
                                    end
                                end
                            end
                            if p.constructorExpr then
                                recordConstructorExprFields(p.key, p.constructorExpr,
                                    lhsExpr, taintSet, fieldTaintSet, registry)
                            elseif not rhs and p.multiExpr and p.multiIndex then
                                -- F5b: spill twin of the record above —
                                -- runs AFTER the strong-update clearing,
                                -- so result 2 of an element-secret
                                -- pcall/xpcall is clear-then-record: the
                                -- fresh container's marker replaces
                                -- whatever the slot held. Non-element
                                -- shapes record nothing here.
                                recordConstructorExprFields(p.key, p.multiExpr,
                                    lhsExpr, taintSet, fieldTaintSet, registry,
                                    p.multiIndex)
                            end
                            if not p.tainted
                                and (p.contentClean or p.aliasRecorded) then
                                -- A definite write to this concrete slot wins
                                -- over an older `root[*]` may-edge for exactly
                                -- this spelling (and, for replacement values,
                                -- its descendants). Other concrete children
                                -- remain possible aliases.
                                fnEventCtx.markMayAliasConcreteClean(
                                    p.key, true)
                            end
                        end
                    elseif rhs or (p.multiExpr and p.multiIndex) then
                        -- Keyless (volatile/unkeyable) write of a TAINTED
                        -- value (round-9b/9d): no sound key exists to record
                        -- the write (`updateInfo.sub[k] = Source()`), so
                        -- record a CONTAMINATION MARKER at the chain's
                        -- deepest stable prefix — fieldTaintSet is heap
                        -- state, so the marker survives terminating branches
                        -- and later invocations (a taintSet-based root
                        -- re-taint would roll back with the branch locals).
                        -- Marked independent so gate clears never bless it.
                        -- Clean writes stay keyless no-ops.  Payload roots
                        -- additionally poison (raw + canon): copies and
                        -- proofs must not treat the table as payload-pure.
                        if p.rawRoot then invalidateSafeRoot(p.rawRoot) end
                        if p.alias and p.alias.canon and p.wildAliasSlot then
                            -- Inline because walkStatements already sits at
                            -- Lua 5.1's 60-upvalue ceiling.
                            fnEventCtx.chainAliasMay =
                                fnEventCtx.chainAliasMay or {}
                            local function link(from, to)
                                local set = fnEventCtx.chainAliasMay[from]
                                if not set then
                                    set = {}
                                    fnEventCtx.chainAliasMay[from] = set
                                end
                                set[to] = true
                            end
                            link(p.wildAliasSlot, p.alias.canon)
                            link(p.alias.canon, p.wildAliasSlot)
                            fnEventCtx.refreshMayAliasEdge(fnEventCtx,
                                p.wildAliasSlot, p.alias.canon, true)
                            fnEventCtx.refreshMayAliasEdge(fnEventCtx,
                                p.alias.canon, p.wildAliasSlot, true)
                            fnEventCtx.invalidateMayAliasCache(fnEventCtx)
                        end
                        if p.tainted then
                            if p.prefix then
                                local marker = p.prefix .. "[*]"
                                fnEventCtx.invalidateMayAliasCache(
                                    fnEventCtx)
                                fieldTaintSet[marker] = true
                                -- Marker provenance mirrors the keyed path.
                                if fnKeyProvenance then
                                    local provRoot = marker:match("^([%a_][%w_]*)")
                                    local provNode = chainRootVarNode(lhsExpr)
                                    local provId
                                    if provNode and provNode.Name == provRoot then
                                        provId = fnOuterVarNodes
                                            and fnOuterVarNodes[provNode] or nil
                                        provId = provId
                                            and effectiveBindingId(provId, provNode)
                                    end
                                    fnKeyProvenance[marker] = provId
                                end
                                exportPersistentKey(marker, lhsExpr)
                                if fnEventCtx then
                                    fnEventCtx.independentFields = fnEventCtx.independentFields or {}
                                    fnEventCtx.independentFields[marker] = true
                                end
                            end
                            if fnEventCtx and fnEventCtx.payloadNames then
                                local rawRoot, root = p.rawRoot, p.canonRoot
                                if root and (fnEventCtx.payloadNames[root]
                                    or fnEventCtx.payloadNames[rawRoot]) then
                                    markIndependentTaint(root)
                                    fnEventCtx.aliasPoisoned = fnEventCtx.aliasPoisoned or {}
                                    fnEventCtx.aliasPoisoned[root] = true
                                    if rawRoot ~= root then
                                        markIndependentTaint(rawRoot)
                                        fnEventCtx.aliasPoisoned[rawRoot] = true
                                    end
                                end
                            end
                        end
                    end
                end
                -- Other LHS shapes (call bases and the like): the RHS was
                -- already walked for sinks/probe-order in pass 1.
            end
            -- Extra RHS expressions beyond the LHS count are still evaluated
            -- (then discarded) — walk them for sinks/probe-order too.
            for i = #lhsList + 1, #rhsList do
                walkExprTop(rhsList[i], taintSet, fieldTaintSet, findings, registry, filePath)
            end
        elseif t == "IfStatement" then
            -- Branch-aware: snapshot taint on entry, walk each clause on a
            -- private copy, then union the exits back into taintSet in-place.
            -- Guards (IsSecretValue/HasSecretValue) untaint locals in the
            -- appropriate branch; the union restores taint after the if/end.
            local entrySnapshot = {}
            for k, v in pairs(taintSet) do entrySnapshot[k] = v end
            local entryFieldSnapshot = {}
            for k, v in pairs(fieldTaintSet) do entryFieldSnapshot[k] = v end
            local entrySafeRefs = copySafeRefs()

            local branchExits = {}
            local branchFieldExits = {}
            local branchSafeExits = {}
            -- Round-8 clause-falsity propagation: reaching ANY clause after a
            -- `Guard(x)` clause — elseif or else — means that condition was
            -- FALSE, i.e. x proved non-secret there (the old pendingUntaint
            -- applied this to a bare else only).  The same falsity argument
            -- covers the fall-through path (no clause taken).
            local subsequentUntaint = {}
            local fallThroughUntaint = {}
            local subsequentSafeRefs = {}
            local fallThroughSafeRefs = {}
            -- Restriction-gate dominance (mirrors preconditionScanBody):
            -- reaching a clause after a restricted-implies-true condition
            -- proves the state was unrestricted when that condition ran.
            local priorsProve = false
            -- First-clause bail flip (`if gate() then return end`): code after
            -- the if runs unrestricted — payload-class taint is clear there.
            local postIfUnrestricted = false
            do
                local first = stmt.Clauses[1]
                if first and first.Condition
                    and restrictedImpliesTrue(first.Condition, registry, fnAliases)
                    and bodyTerminates(first.Body) then
                    postIfUnrestricted = true
                end
            end

            -- Round-8e/8f: path-scoped provenance state.  Every clause walks
            -- from the entry snapshot; only REACHABLE (non-terminating)
            -- exits merge, and the entry state joins the merge only when a
            -- fall-through path exists (no bare else).
            local provEntry = copyProvState(fnEventCtx)
            local provContribs = provEntry and {} or nil
            local chainDisagreements = nil
            local aliasDisagreements = nil
            -- Independent-field marks are HEAP state (see the merge below):
            -- unioned across every clause, terminating ones included.
            local independentUnion = provEntry and {} or nil
            local hasElse = false
            for _, clause in ipairs(stmt.Clauses) do
                if not clause.Condition then hasElse = true end
            end
            local remainingSecretEvents = fnEventCtx and copyEventSet(
                fnEventCtx.activeSecretEvents or fnEventCtx.secretEvents) or nil

            -- Round-13b (Drew's 12d canon): a guard-secret-dominated branch
            -- may route the opaque value to a documented C sink or
            -- reject/defer — it must NOT manufacture ordinary truth/
            -- presence/activity. Literal returns and literal state writes in
            -- the region flag <secret-collapse>; deliberate policies carry
            -- `-- @secret-policy: <name>` (the ONLY suppression that works
            -- on this sink — @secret-safe deliberately does not).
            -- Known non-goals (documented in the .taintrc header): bare
            -- Show()/Hide() calls in the region, literals laundered through
            -- a local, stored-boolean guards.
            -- 60-upvalue rule: these closures capture ONLY names already
            -- referenced by walkStatements (emit, nodeLine, stripParens are
            -- existing upvalues; findings/filePath are parameters) — zero
            -- new upvalues on the walker.
            local function collapseLiteralish(e)
                e = stripParens(e)
                if type(e) ~= "table" then return false end
                local at = e.AstType
                if at == "NilExpr" or at == "BooleanExpr"
                    or at == "NumberExpr" or at == "StringExpr" then
                    return true
                end
                if at == "UnopExpr" then return collapseLiteralish(e.Rhs) end
                if at == "ConstructorExpr" then
                    for _, en in ipairs(e.EntryList or {}) do
                        if en.Value and not collapseLiteralish(en.Value) then
                            return false
                        end
                    end
                    return true
                end
                return false
            end
            -- Dedup is two-layered: collapseSeen dedupes within THIS
            -- IfStatement visit; the findings linear scan dedupes across
            -- visits (an outer region scan descending into a nested guard-if
            -- and that nested if's own visit hold DIFFERENT collapseSeen
            -- tables but can flag the same statement).
            local collapseSeen = {}
            local function emitCollapse(key, ln, msg)
                if collapseSeen[key] then return end
                collapseSeen[key] = true
                for _, prior in ipairs(findings) do
                    if prior.line == ln and prior.file == filePath
                        and prior.sink == "<secret-collapse>" then
                        return
                    end
                end
                emit(findings, filePath, ln, 1,
                    "<secret-collapse>", "<tainted-local>", msg)
            end
            local function scanCollapse(body)
                for _, s in ipairs(body or {}) do
                    local at = s.AstType
                    if at == "ReturnStatement" then
                        local args = s.Arguments or {}
                        if #args > 0 then
                            local allLit = true
                            for _, e in ipairs(args) do
                                if not collapseLiteralish(e) then allLit = false break end
                            end
                            if allLit then
                                local ln = nodeLine(s) or 0
                                emitCollapse("r" .. ln, ln,
                                    "guard-secret branch manufactures ordinary"
                                    .. " state (returns literal(s)) — secrecy is"
                                    .. " indeterminate: route the value to a"
                                    .. " documented C sink or reject/defer;"
                                    .. " a deliberate policy needs"
                                    .. " `-- @secret-policy: <name>`")
                            end
                        end
                    elseif at == "AssignmentStatement" then
                        local stateLhs = false
                        for _, l in ipairs(s.Lhs or {}) do
                            local lt = stripParens(l)
                            if lt and (lt.AstType == "MemberExpr"
                                or lt.AstType == "IndexExpr") then
                                stateLhs = true
                                break
                            end
                        end
                        if stateLhs and #(s.Rhs or {}) > 0 then
                            local allLit = true
                            for _, e in ipairs(s.Rhs) do
                                if not collapseLiteralish(e) then allLit = false break end
                            end
                            if allLit then
                                local ln = nodeLine(s) or 0
                                emitCollapse("a" .. ln, ln,
                                    "guard-secret branch writes literal state —"
                                    .. " secrecy is indeterminate: reject/defer or"
                                    .. " name the policy with"
                                    .. " `-- @secret-policy: <name>`")
                            end
                        end
                    elseif at == "IfStatement" then
                        for _, c in ipairs(s.Clauses or {}) do
                            if c.Body then scanCollapse(c.Body.Body) end
                        end
                    elseif at == "DoStatement" or at == "WhileStatement"
                        or at == "RepeatStatement"
                        or at == "NumericForStatement"
                        or at == "GenericForStatement" then
                        if s.Body then scanCollapse(s.Body.Body) end
                    end
                    -- Function statements / closures deliberately skipped:
                    -- deferred bodies execute outside the guard's dominance.
                end
            end
            local collapseRegionForLater = false

            for _, clause in ipairs(stmt.Clauses) do
                if provEntry then setProvState(fnEventCtx, provEntry) end
                safeRefSet = {}
                for key in pairs(entrySafeRefs) do safeRefSet[key] = true end
                for key in pairs(subsequentSafeRefs) do safeRefSet[key] = true end
                -- Each branch starts from the pre-if entry state.
                local branchTaint = {}
                for k, v in pairs(entrySnapshot) do branchTaint[k] = v end
                local branchFieldTaint = {}
                for k, v in pairs(entryFieldSnapshot) do branchFieldTaint[k] = v end
                for n in pairs(subsequentUntaint) do branchTaint[n] = nil end

                local unrestrictedBranch = priorsProve
                local suppressSpill = false
                local branchSecretEvents = remainingSecretEvents
                    and copyEventSet(remainingSecretEvents) or nil
                local branchVarargSecret
                -- Round-13b: an else/elseif clause AFTER an untaint-then
                -- guard (`if not issecretvalue(x)`) runs only when the value
                -- WAS secret — it inherits the secret region.
                local scanCollapseHere = collapseRegionForLater
                if clause.Condition then
                    if remainingSecretEvents then
                        local onTrue, onFalse = refineSecretEvents(
                            clause.Condition, remainingSecretEvents)
                        if onTrue then
                            branchSecretEvents = onTrue
                            remainingSecretEvents = onFalse
                        end
                    end
                    if branchSecretEvents then
                        branchVarargSecret = restrictPayloadToEvents(branchTaint,
                            branchFieldTaint, branchSecretEvents)
                        suppressSpill = not next(branchVarargSecret)
                    end
                    local guarded = analyzeGuard(clause.Condition, registry)
                    if guarded then
                        if guarded.kind == "untaint-then" then
                            -- `not Guard(x)` → untaint x in this (then) branch
                            for _, n in ipairs(guarded.locals) do
                                branchTaint[n] = nil
                            end
                            markSafeRefs(guarded.refs)
                            -- Round-13b: every LATER clause of this
                            -- if-statement runs when the probe said SECRET.
                            collapseRegionForLater = true
                        elseif guarded.kind == "untaint-else" then
                            -- `Guard(x)` → x stays tainted in this branch;
                            -- every LATER clause and the fall-through path
                            -- run only when this condition was false.
                            for _, n in ipairs(guarded.locals) do
                                subsequentUntaint[n] = true
                                fallThroughUntaint[n] = true
                            end
                            for _, key in ipairs(guarded.refs or {}) do
                                subsequentSafeRefs[key] = true
                                fallThroughSafeRefs[key] = true
                            end
                            -- Round-13b: THIS clause body is the secret
                            -- region (`if issecretvalue(x) then` was TRUE).
                            scanCollapseHere = true
                        end
                    else
                        -- Not a guard pattern — walk condition normally for sinks
                        walkConditionExpr(clause.Condition, branchTaint, branchFieldTaint, findings, registry, filePath)
                    end
                    if condTrueImpliesUnrestricted(clause.Condition, registry) then
                        -- `if not gate() then` — this branch runs only
                        -- UNRESTRICTED: payload-class taint is clear here.
                        unrestrictedBranch = true
                    end
                    priorsProve = priorsProve
                        or (restrictedImpliesTrue(clause.Condition, registry, fnAliases) ~= nil)
                end
                if not clause.Condition and branchSecretEvents then
                    branchVarargSecret = restrictPayloadToEvents(branchTaint,
                        branchFieldTaint, branchSecretEvents)
                    suppressSpill = not next(branchVarargSecret)
                end
                if unrestrictedBranch then
                    clearPayloadRootedTaint(branchTaint, branchFieldTaint)
                end

                if clause.Body and clause.Body.Body then
                    if scanCollapseHere then
                        scanCollapse(clause.Body.Body)
                    end
                    local prevSuppress = fnEventCtx and fnEventCtx.suppressSpill
                    local prevVararg = fnEventCtx and fnEventCtx.varargSecret
                    local prevActiveEvents = fnEventCtx and fnEventCtx.activeSecretEvents
                    if suppressSpill and fnEventCtx then
                        fnEventCtx.suppressSpill = true
                    end
                    if fnEventCtx and branchVarargSecret then
                        fnEventCtx.varargSecret = branchVarargSecret
                        fnEventCtx.activeSecretEvents = branchSecretEvents
                    end
                    walkStatements(clause.Body.Body, branchTaint, branchFieldTaint, findings, registry, filePath, debug)
                    if fnEventCtx then
                        fnEventCtx.suppressSpill = prevSuppress
                        fnEventCtx.varargSecret = prevVararg
                        fnEventCtx.activeSecretEvents = prevActiveEvents
                    end
                end

                -- Round-8: a branch whose body unconditionally leaves the
                -- function never reaches the post-if state — its LOCAL exit
                -- state (taintSet, payload/alias provenance) rolls back and
                -- must not poison the union.  This is what makes the shipped
                -- bail idiom (`if IsSecretValue(x) then return end; use x`)
                -- analyze clean now that unproven truth-tests emit.
                -- FIELD state is different (round-8h): fieldTaintSet is a
                -- HEAP approximation (round-7k), and a field written on a
                -- terminated path persists into LATER invocations of the
                -- function that DO reach the post-if code — so field taint
                -- and its independent-provenance marks always merge,
                -- terminating branches included.
                -- Invocation-local exception (round-8i): fields of FRESH
                -- non-escaping tables die with the invocation — a terminated
                -- branch's writes to them roll back with the locals instead
                -- of joining the heap union.  Round-8k: the same holds for a
                -- scratch table freshly bound INSIDE the terminated branch
                -- (`if bad then local tmp = {} ... return end`) — it is
                -- block-local, so the branch-body freshness scan covers what
                -- the function-level scan (which must reject nested bindings
                -- as possible shadows, round-8j) cannot.
                local terminates = bodyTerminates(clause.Body)
                local branchFresh = terminates and collectFreshTables(clause.Body) or nil
                local function rolledBack(root)
                    if not (terminates and root) then return false end
                    if fnFreshTables and fnFreshTables[root] then return true end
                    return (branchFresh and branchFresh[root]) or false
                end
                local exitFieldTaint = branchFieldTaint
                if terminates
                    and ((fnFreshTables and next(fnFreshTables)) or next(branchFresh)) then
                    exitFieldTaint = {}
                    for k, v in pairs(branchFieldTaint) do
                        if not rolledBack(k:match("^([%w_]+)")) then
                            exitFieldTaint[k] = v
                        end
                    end
                end
                branchFieldExits[#branchFieldExits + 1] = exitFieldTaint
                if independentUnion and fnEventCtx and fnEventCtx.independentFields then
                    for k in pairs(fnEventCtx.independentFields) do
                        if not rolledBack(k:match("^([%w_]+)")) then
                            independentUnion[k] = true
                        end
                    end
                end
                if not terminates then
                    branchExits[#branchExits + 1] = branchTaint
                    branchSafeExits[#branchSafeExits + 1] = copySafeRefs()
                    if provContribs then
                        provContribs[#provContribs + 1] =
                            { taint = branchTaint, prov = copyProvState(fnEventCtx) }
                    end
                end
            end
            if provEntry then
                local contributions = {}
                if not hasElse then
                    contributions[1] = { taint = entrySnapshot, prov = provEntry }
                end
                for _, con in ipairs(provContribs) do
                    contributions[#contributions + 1] = con
                end
                if #contributions == 0 then
                    -- Post-if state unreachable (every clause terminates and
                    -- an else exists) — keep the entry state, it is moot.
                    contributions[1] = { taint = entrySnapshot, prov = provEntry }
                end
                chainDisagreements, aliasDisagreements =
                    applyMergedProvState(fnEventCtx, contributions)
                -- Heap re-union (round-8h): independent marks from EVERY
                -- clause, terminating ones included, survive the merge.
                for k in pairs(independentUnion) do
                    fnEventCtx.independentFields[k] = true
                end
            end

            -- A field proof survives the if only when it holds on EVERY
            -- reachable exit.  The no-else fall-through receives falsity
            -- proofs from preceding guard clauses; terminating branches do
            -- not contribute.
            local safeContribs = {}
            if not hasElse then
                local fall = {}
                for key in pairs(entrySafeRefs) do fall[key] = true end
                for key in pairs(fallThroughSafeRefs) do fall[key] = true end
                safeContribs[#safeContribs + 1] = fall
            end
            for _, refs in ipairs(branchSafeExits) do
                safeContribs[#safeContribs + 1] = refs
            end
            if #safeContribs == 0 then safeContribs[1] = entrySafeRefs end
            local mergedSafe = {}
            for key in pairs(safeContribs[1]) do
                local all = true
                for i = 2, #safeContribs do
                    if not safeContribs[i][key] then all = false break end
                end
                if all then mergedSafe[key] = true end
            end
            safeRefSet = mergedSafe

            -- Mutate taintSet in-place to the union of all reachable exits.
            -- Entry contributes only when there is a real no-clause-taken
            -- fall-through path; an exhaustive else must not resurrect values
            -- every arm definitely overwrote.
            for k in pairs(taintSet) do taintSet[k] = nil end
            if not hasElse then
                for k, v in pairs(entrySnapshot) do
                    if v and not fallThroughUntaint[k] then taintSet[k] = true end
                end
            end
            for _, b in ipairs(branchExits) do
                for k, v in pairs(b) do
                    if v then taintSet[k] = true end
                end
            end
            -- Same union for fieldTaintSet.
            for k in pairs(fieldTaintSet) do fieldTaintSet[k] = nil end
            if not hasElse then
                for k, v in pairs(entryFieldSnapshot) do
                    if v then fieldTaintSet[k] = true end
                end
            elseif stmt._quiEscapedDefiniteRebinds
                or stmt._quiDirtyDefiniteRebinds then
                -- Every arm may install a fresh identity, but an identity
                -- escaped as a whole in every-arm control flow can still
                -- alias persistent heap evidence under the same spelling.
                -- Keep only entry fields rooted at those escaped merge
                -- identities; ordinary exhaustive overwrites remain kills.
                for k, v in pairs(entryFieldSnapshot) do
                    local root = k:match("^([%a_][%w_]*)")
                    local dirty = root and stmt._quiDirtyDefiniteRebinds
                        and stmt._quiDirtyDefiniteRebinds[root]
                    local dirtied = dirty and (dirty[k] == true)
                    if not dirtied and dirty then
                        for marker in pairs(dirty) do
                            if marker:sub(-3) == "[*]" then
                                local prefix = marker:sub(1, -4)
                                if k:sub(1, #prefix + 1) == prefix .. "."
                                    or k:sub(1, #prefix + 1) == prefix .. "[" then
                                    dirtied = true
                                    break
                                end
                            end
                        end
                    end
                    if v and root and (
                        (stmt._quiEscapedDefiniteRebinds
                            and stmt._quiEscapedDefiniteRebinds[root])
                        or dirtied) then
                        fieldTaintSet[k] = true
                    end
                end
            end
            for _, b in ipairs(branchFieldExits) do
                for k, v in pairs(b) do
                    if v then fieldTaintSet[k] = true end
                end
            end
            -- Chain-alias DISAGREEMENTS (round-9f): a slot linked to
            -- different tables on different paths has no single identity.
            -- If any surviving path recorded taint under the slot or any of
            -- its possible targets, the slot may hold that secret —
            -- contamination-mark it (independent, so gate clears keep it);
            -- with no taint in sight the link persists as a MAY-alias
            -- (round-10d) so a LATER write through a target stays visible.
            -- Runs AFTER the field union so branch-written keys count.
            -- (Shared helper — the loop merge routes through it too.)
            materializeFlowDisagreements(fnEventCtx, chainDisagreements,
                aliasDisagreements, fieldTaintSet)
            if postIfUnrestricted then
                clearPayloadRootedTaint(taintSet, fieldTaintSet)
            end
        elseif t == "ReturnStatement" then
            if stmt.Arguments then
                for _, a in ipairs(stmt.Arguments) do
                    walkExprTop(a, taintSet, fieldTaintSet, findings, registry, filePath)
                end
            end
        elseif t == "BreakStatement" then
            -- Direct-break exit snapshot (round-10d follow-up 4): the
            -- enclosing repeat's merge needs the flow state AS OF each
            -- break — a blanket entry re-admission over-kept state that a
            -- PRE-break rebind had already replaced (statement-order FP:
            -- `repeat h = {}; if Y then break end until Z` is guaranteed
            -- replacement on every exit). Nested loops and closures mask
            -- the collector: their breaks bind them / cannot cross the
            -- function boundary.
            -- Dead break sites never reach this branch: the reachability
            -- skip above drops them before dispatch (follow-ups 5+6).
            local bc = fnEventCtx and fnEventCtx.breakExitCollector
            if bc then
                bc[#bc + 1] = {
                    taint = copySet(taintSet),
                    field = copySet(fieldTaintSet),
                    safe = copySafeRefs(),
                    prov = copyProvState(fnEventCtx),
                }
            end
        elseif t == "CallStatement" then
            -- Standalone call expression (e.g. print(x), SomeAPI:method(x))
            if stmt.Expression then
                walkExprTop(stmt.Expression, taintSet, fieldTaintSet, findings, registry, filePath)
            end
        elseif t == "DoStatement" then
            -- Plain `do … end` block (round-6b: these bodies were silently
            -- skipped — an entire blind spot for every rule in this walker).
            -- walkStatements snapshots/restores its lexical locals while
            -- preserving writes through aliases to outer heap objects.
            if stmt.Body and stmt.Body.Body then
                walkStatements(stmt.Body.Body, taintSet, fieldTaintSet, findings, registry, filePath, debug)
            end
        elseif t == "GenericForStatement"
            or t == "NumericForStatement"
            or t == "WhileStatement"
            or t == "RepeatStatement" then
            -- Numeric/generic headers execute once before the loop. A while
            -- condition executes at the head on every back-edge and is walked
            -- by the transfer below against the converged head state.
            -- Header walk is hoisted to walkLoopHeaderExprs (round-23:
            -- walkStatements sits at the 60-upvalue ceiling; the helper
            -- replaces the walkNumericForExpr capture net-zero).
            -- elementForValueVar: generic-for VALUE binder to taint after
            -- each loop-var shadow-clear when the header was the suppressed
            -- element-container shape (true = suppressed, no value binder).
            local elementForValueVar = walkLoopHeaderExprs(t, stmt, taintSet,
                fieldTaintSet, findings, registry, filePath)
            if elementForValueVar == true then elementForValueVar = nil end

            local body = stmt.Body
            if body and body.Body then
                local function captureState()
                    return {
                        taint = copySet(taintSet),
                        field = copySet(fieldTaintSet),
                        safe = copySafeRefs(),
                        prov = copyProvState(fnEventCtx),
                    }
                end
                local function restoreState(state)
                    for key in pairs(taintSet) do taintSet[key] = nil end
                    for key, value in pairs(state.taint or {}) do
                        taintSet[key] = value
                    end
                    for key in pairs(fieldTaintSet) do fieldTaintSet[key] = nil end
                    for key, value in pairs(state.field or {}) do
                        fieldTaintSet[key] = value
                    end
                    if fnEventCtx and state.prov then
                        setProvState(fnEventCtx, state.prov)
                    end
                    safeRefSet = {}
                    for key in pairs(state.safe or {}) do safeRefSet[key] = true end
                end
                local function deepEqual(a, b, seen)
                    if a == b then return true end
                    if type(a) ~= type(b) then return false end
                    if type(a) ~= "table" then return false end
                    seen = seen or {}
                    if seen[a] == b then return true end
                    seen[a] = b
                    for key, value in pairs(a) do
                        if not deepEqual(value, b[key], seen) then return false end
                    end
                    for key in pairs(b) do
                        if a[key] == nil then return false end
                    end
                    return true
                end
                local function mergeStates(states)
                    if #states == 0 then return nil end
                    for key in pairs(taintSet) do taintSet[key] = nil end
                    for key in pairs(fieldTaintSet) do fieldTaintSet[key] = nil end
                    local contributions = {}
                    for _, state in ipairs(states) do
                        for key, value in pairs(state.taint or {}) do
                            if value then taintSet[key] = true end
                        end
                        for key, value in pairs(state.field or {}) do
                            if value then fieldTaintSet[key] = true end
                        end
                        if state.prov then
                            contributions[#contributions + 1] = {
                                taint = state.taint,
                                prov = state.prov,
                            }
                        end
                    end
                    if fnEventCtx and #contributions > 0 then
                        local chainDiffs, aliasDiffs = applyMergedProvState(
                            fnEventCtx, contributions)
                        materializeFlowDisagreements(fnEventCtx, chainDiffs,
                            aliasDiffs, fieldTaintSet)
                    end
                    safeRefSet = {}
                    for key in pairs(states[1].safe or {}) do
                        local all = true
                        for i = 2, #states do
                            if not (states[i].safe and states[i].safe[key]) then
                                all = false
                                break
                            end
                        end
                        if all then safeRefSet[key] = true end
                    end
                    return captureState()
                end
                local function shadowLoopVariables()
                    local vars = {}
                    if t == "NumericForStatement" then
                        if stmt.Variable and stmt.Variable.Name then
                            vars[#vars + 1] = stmt.Variable.Name
                        end
                    elseif t == "GenericForStatement" then
                        for _, variable in ipairs(stmt.VariableList or {}) do
                            if variable.Name then vars[#vars + 1] = variable.Name end
                        end
                    end
                    local saved = {}
                    for _, name in ipairs(vars) do
                        local ctx = fnEventCtx
                        saved[name] = {
                            tainted = taintSet[name] == true,
                            aliasCanon = ctx and ctx.aliasCanon[name] or nil,
                            aliasPoisoned = ctx and ctx.aliasPoisoned[name] == true or false,
                            fields = takeRooted(fieldTaintSet, name),
                            independent = takeRooted(ctx and ctx.independentFields, name),
                            provenance = takeRooted(fnKeyProvenance, name),
                            safe = takeRooted(safeRefSet, name),
                        }
                        taintSet[name] = nil
                        if ctx then
                            ctx.aliasCanon[name] = nil
                            ctx.aliasPoisoned[name] = nil
                        end
                    end
                    return saved
                end
                local function restoreLoopVariables(saved)
                    local ctx = fnEventCtx
                    for name, state in pairs(saved or {}) do
                        taintSet[name] = state.tainted and true or nil
                        if ctx then
                            ctx.aliasCanon[name] = state.aliasCanon
                            ctx.aliasPoisoned[name] =
                                state.aliasPoisoned and true or nil
                        end
                        restoreRooted(fieldTaintSet, name, state.fields)
                        restoreRooted(ctx and ctx.independentFields, name,
                            state.independent)
                        restoreRooted(fnKeyProvenance, name, state.provenance)
                        restoreRooted(safeRefSet, name, state.safe)
                    end
                end
                local function transfer(head, outFindings)
                    restoreState(head)
                    if t == "WhileStatement" and stmt.Condition then
                        walkConditionExpr(stmt.Condition, taintSet,
                            fieldTaintSet, outFindings, registry, filePath)
                    end
                    local loopVars = shadowLoopVariables()
                    -- Round-23: elements of the iterated container are
                    -- possibly secret — taint the VALUE binder for the body
                    -- walk, AFTER the shadow-clear so the fresh per-iteration
                    -- binding (not the shadowed outer spelling) carries it.
                    -- The KEY binder (VariableList position 1) stays clean.
                    if elementForValueVar then
                        taintSet[elementForValueVar] = true
                    end
                    local previousCollector =
                        fnEventCtx and fnEventCtx.breakExitCollector
                    local breakExits = {}
                    if fnEventCtx then
                        fnEventCtx.breakExitCollector = breakExits
                    end
                    local deferredLocalRestore = walkStatements(body.Body,
                        taintSet, fieldTaintSet, outFindings, registry,
                        filePath, debug, t == "RepeatStatement"
                            and { deferLocalRestore = true } or nil)
                    if t == "RepeatStatement" and stmt.Condition then
                        walkConditionExpr(stmt.Condition, taintSet,
                            fieldTaintSet, outFindings, registry, filePath)
                    end
                    if fnEventCtx then
                        fnEventCtx.breakExitCollector = previousCollector
                    end
                    local rawBodyExit = captureState()
                    local function normalizeExit(state)
                        restoreState(state)
                        if deferredLocalRestore then deferredLocalRestore() end
                        restoreLoopVariables(loopVars)
                        return captureState()
                    end
                    local bodyExit = normalizeExit(rawBodyExit)
                    local normalizedBreaks = {}
                    for _, breakState in ipairs(breakExits) do
                        normalizedBreaks[#normalizedBreaks + 1] =
                            normalizeExit(breakState)
                    end
                    restoreState(bodyExit)
                    return bodyExit, normalizedBreaks
                end

                local entryState = captureState()
                local headState = entryState
                local bodyFallsThrough = not bodyTerminates(body)
                while true do
                    local bodyExit = transfer(headState, {})
                    local headInputs = { entryState }
                    if bodyFallsThrough then
                        headInputs[#headInputs + 1] = bodyExit
                    end
                    local nextHead = mergeStates(headInputs)
                    if deepEqual(nextHead, headState) then
                        headState = nextHead
                        break
                    end
                    headState = nextHead
                end

                -- Emit exactly once from the converged head, then join every
                -- reachable loop exit: zero iterations for while/for, normal
                -- condition exits, and each statement-order break snapshot.
                local bodyExit, breakExits = transfer(headState, findings)
                local exitStates = {}
                if t ~= "RepeatStatement" then
                    exitStates[#exitStates + 1] = entryState
                end
                if bodyFallsThrough then
                    exitStates[#exitStates + 1] = bodyExit
                end
                for _, breakState in ipairs(breakExits or {}) do
                    exitStates[#exitStates + 1] = breakState
                end
                if #exitStates > 0 then
                    mergeStates(exitStates)
                else
                    -- Post-loop code is unreachable; retain a deterministic
                    -- state for the enclosing dead-code machinery.
                    restoreState(entryState)
                end
            end
        end
        -- Reachability update (round-10d follow-ups 5+6): everything
        -- after a flow-ending statement in THIS block is dead code.
        -- flowMode call through bodyTerminates: this walker sits at the
        -- 60-upvalue cap — bodyTerminates is already captured,
        -- stmtEndsFlow would be a new upvalue.
        if not unreachable and bodyTerminates({ Body = { stmt } }, true) then
            unreachable = true
        end
    end
    if scopeControl and scopeControl.deferLocalRestore then
        return restoreBlockLocals
    end
    restoreBlockLocals()
end

-- ---------------------------------------------------------------------------
-- Precondition-guarded API scan
-- ---------------------------------------------------------------------------
-- APIs whose api-index entry carries `preconditions` (RequiresUnitAuraAccess
-- etc.) HARD-ERROR under encounter/M+/PvP addon restrictions
-- (SecretPredicatesDocumentation: FailureMode = "Error"). A raw call is a
-- live crash path the secret-flow checks above never see — the 2026-07
-- external review found three shipped callers that way. This pass flags
-- every direct call to such an API at REVIEW tier unless the call is
-- "handled": lexically inside a scope that consults a restriction gate
-- (C_Secrets.ShouldAurasBeSecret), inside a pcall/xpcall-protected closure,
-- or the API is passed to pcall/xpcall as the protected function (that shape
-- is a reference, not a CallExpr, so it never flags). Scope gating is
-- order-insensitive and lexical — non-interprocedural, so a caller-side gate
-- needs a `-- @secret-safe: <reason>` annotation like every other heuristic.

-- File-local alias resolution (built by collectPreconditionAliases):
--   aliases.map[localName] = canonical dotted name (guarded API or gate)
--   aliases.ns[localName]  = canonical namespace ("C_UnitAuras", "C_Secrets")
-- Resolves `local Get = C_UnitAuras.GetUnitAuras; Get(...)` and
-- `local UA = C_UnitAuras; UA.GetUnitAuras(...)` call names back to their
-- canonical form for both the guarded-API and restriction-gate lookups.
local function resolveAliasedName(name, aliases)
    if not name or not aliases then return name end
    if aliases.map[name] then return aliases.map[name] end
    local prefix, rest = name:match("^([%w_]+)([.:].+)$")
    if prefix and aliases.ns[prefix] then
        return aliases.ns[prefix] .. rest
    end
    return name
end

-- Gate recognition is PROTECTION-GRANTING, so unlike the finding-emitting API
-- resolution it must not trust an alias name that the file ever binds to
-- anything else (round-6: the file-scope alias union ignored scope and
-- reassignment, so `local isSecret = C_Secrets.ShouldAurasBeSecret` in one
-- scope let an UNRELATED `isSecret` elsewhere suppress real findings).
-- aliases.poisoned holds names with conflicting bindings (see the fixpoint in
-- M.analyze); a poisoned hop grants no protection. Direct registry names
-- (extra_restriction_gates wrappers) are unaffected.
local function isGateName(name, registry, aliases)
    if not name then return false end
    if registry:isRestrictionGate(name) then
        -- Direct-hit shadow rule, mirroring isGuardName plus the
        -- receiver-aware discipline of isGuardMethodName: gate credit is
        -- PROTECTION-GRANTING, so a direct registry hit must be an exact
        -- unshadowed identity.
        --   * A gate NAME the file rebinds to anything other than itself is
        --     shadowed and takes no DIRECT credit. Self-canonical bindings
        --     keep it — bare or _G-qualified (normalized in harvest);
        --     binds[name] == false records a non-canonical binding.
        --   * A DOTTED gate additionally requires an unpoisoned, unrebound
        --     namespace prefix (`local C_Secrets = <impostor>` must not
        --     smuggle protection through the registered dotted spelling —
        --     binds only keys simple names, so the full-name check alone
        --     never sees that shadow).
        -- A shadowed name FALLS THROUGH to the alias map rather than
        -- failing outright: the binding may itself be a registered gate
        -- alias (`local isSecret = C_Secrets.ShouldAurasBeSecret`), which
        -- the map path below credits — an early false revoked exactly that
        -- idiom repo-wide on the guard side. Scope: BUILTIN gate names only
        -- — .taintrc extra_restriction_gates wrappers are
        -- function-literal-bound in their defining file by construction.
        if not registry:isBuiltinGate(name) then return true end
        local binds = aliases and aliases.binds
        local poisonedDirect = (aliases and aliases.poisoned) or {}
        local shadowed = binds and binds[name] ~= nil
            and binds[name] ~= name
            and binds[name] ~= ("_G." .. name)
        if not shadowed then
            local prefix = name:match("^([%w_]+)%.")
            if prefix then
                shadowed = poisonedDirect[prefix] == true
                    or (binds and binds[prefix] ~= nil
                        and binds[prefix] ~= prefix
                        and binds[prefix] ~= ("_G." .. prefix))
            end
        end
        if not shadowed then return true end
    end
    if not aliases then return false end
    local poisoned = aliases.poisoned or {}
    if aliases.map[name] then
        return (not poisoned[name]) and registry:isRestrictionGate(aliases.map[name])
    end
    local prefix, rest = name:match("^([%w_]+)([.:].+)$")
    if prefix and aliases.ns[prefix] then
        return (not poisoned[prefix])
            and registry:isRestrictionGate(aliases.ns[prefix] .. rest)
    end
    return false
end

-- Gate polarity of an if-clause condition:
--   "positive": condition true implies RESTRICTED — a bare gate call,
--     possibly guarded by an `and` chain (`C_Secrets and C_Secrets.X and
--     C_Secrets.X()` — the authored idiom).
--   "negative": condition true implies UNRESTRICTED (`not gate()`,
--     `A and not gate()`).
--   nil: no gate, or an unmodeled shape (gate under `or`,
--     non-boolean-literal comparisons like `gate() ~= nil`) — callers treat
--     the branch as UNKNOWN and inherit their state; unmodeled shapes never
--     grant protection (2026-07 round-4).
local function gateConditionPolarity(cond, registry, aliases)
    if type(cond) ~= "table" then return nil end
    local t = cond.AstType
    if t == "Parentheses" then
        return gateConditionPolarity(cond.Inner, registry, aliases)
    end
    if t == "CallExpr" then
        local name = callTargetName(cond.Base)
        if isGateName(name, registry, aliases) then return "positive" end
        return nil
    end
    if t == "UnopExpr" and cond.Op == "not" then
        local p = gateConditionPolarity(cond.Rhs, registry, aliases)
        if p == "positive" then return "negative" end
        if p == "negative" then return "positive" end
        return nil
    end
    if t == "BinopExpr" and cond.Op == "and" then
        -- `A and gate()`: the whole condition true implies the gate's
        -- verdict; either operand may carry it (the other is just a guard).
        return gateConditionPolarity(cond.Rhs, registry, aliases)
            or gateConditionPolarity(cond.Lhs, registry, aliases)
    end
    if t == "BinopExpr" and (cond.Op == "==" or cond.Op == "~=") then
        -- Boolean-literal comparisons: `gate() == true`, `gate() ~= false`
        -- keep the polarity; `gate() == false`, `gate() ~= true` invert it.
        local lhsIsLit = type(cond.Lhs) == "table" and cond.Lhs.AstType == "BooleanExpr"
        local rhsIsLit = type(cond.Rhs) == "table" and cond.Rhs.AstType == "BooleanExpr"
        local lit = (lhsIsLit and cond.Lhs) or (rhsIsLit and cond.Rhs) or nil
        if lit then
            local other = lhsIsLit and cond.Rhs or cond.Lhs
            local p = gateConditionPolarity(other, registry, aliases)
            if p then
                local keep = (cond.Op == "==" and lit.Value == true)
                    or (cond.Op == "~=" and lit.Value == false)
                if keep then return p end
                return p == "positive" and "negative" or "positive"
            end
        end
        return nil
    end
    return nil
end

-- Dotted name of a bare name/member chain ("C_Secrets",
-- "C_Secrets.ShouldAurasBeSecret"); nil for anything else.
local function nameChainOf(n)
    if type(n) ~= "table" then return nil end
    if n.AstType == "Parentheses" then return nameChainOf(n.Inner) end
    if n.AstType == "VarExpr" or n.AstType == "MemberExpr" then
        return (callTargetName(n))
    end
    return nil
end

-- Is `expr` an existence guard FOR the gate named `gateName` — i.e. a
-- dotted prefix of the gate's own call chain (`C_Secrets`,
-- `C_Secrets.ShouldAurasBeSecret` for gate `C_Secrets.ShouldAurasBeSecret()`),
-- or an `and`-chain of such prefixes? An arbitrary conjunct (`someFlag and
-- gate()`) can be false while restricted and must NOT establish dominance
-- (2026-07 round-4).
local function isGuardPrefixFor(expr, gateName)
    if type(expr) ~= "table" then return false end
    if expr.AstType == "Parentheses" then return isGuardPrefixFor(expr.Inner, gateName) end
    if expr.AstType == "BinopExpr" and expr.Op == "and" then
        return isGuardPrefixFor(expr.Lhs, gateName) and isGuardPrefixFor(expr.Rhs, gateName)
    end
    local name = nameChainOf(expr)
    if not name then return false end
    return gateName == name or gateName:sub(1, #name + 1) == (name .. ".")
end

-- Flip-safety: does a RESTRICTED state GUARANTEE this condition evaluates
-- true? Only then does a terminating body prove the code after the if runs
-- unrestricted. Returns the gate call's SYNTACTIC name on success (the
-- prefix check runs against the name as written, aliases included), nil
-- otherwise. `or` disjuncts are safe (restricted ⇒ the gate disjunct is
-- true ⇒ the whole `or` is true). `and` conjuncts are accepted ONLY when
-- they are existence guards for the gate itself.
restrictedImpliesTrue = function(cond, registry, aliases)
    if type(cond) ~= "table" then return nil end
    local t = cond.AstType
    if t == "Parentheses" then return restrictedImpliesTrue(cond.Inner, registry, aliases) end
    if t == "CallExpr" then
        local name = callTargetName(cond.Base)
        if isGateName(name, registry, aliases) then return name end
        return nil
    end
    if t == "BinopExpr" then
        if cond.Op == "or" then
            return restrictedImpliesTrue(cond.Lhs, registry, aliases)
                or restrictedImpliesTrue(cond.Rhs, registry, aliases)
        end
        if cond.Op == "and" then
            local n = restrictedImpliesTrue(cond.Rhs, registry, aliases)
            if n and isGuardPrefixFor(cond.Lhs, n) then return n end
            n = restrictedImpliesTrue(cond.Lhs, registry, aliases)
            if n and isGuardPrefixFor(cond.Rhs, n) then return n end
            return nil
        end
        if cond.Op == "==" or cond.Op == "~=" then
            local lhsIsLit = type(cond.Lhs) == "table" and cond.Lhs.AstType == "BooleanExpr"
            local rhsIsLit = type(cond.Rhs) == "table" and cond.Rhs.AstType == "BooleanExpr"
            local lit = (lhsIsLit and cond.Lhs) or (rhsIsLit and cond.Rhs) or nil
            if lit then
                local other = lhsIsLit and cond.Rhs or cond.Lhs
                local keep = (cond.Op == "==" and lit.Value == true)
                    or (cond.Op == "~=" and lit.Value == false)
                if keep then return restrictedImpliesTrue(other, registry, aliases) end
            end
        end
    end
    return nil
end

-- Does a clause body (Statlist) unconditionally leave the enclosing
-- function?  `return`, a trailing error() call, a nested if whose clause set
-- covers all paths (bare else present) with every clause body terminating,
-- and a `do` block that terminates all count (round-8g: the nested-if shape
-- previously read as surviving, so an all-paths-return branch still merged
-- its provenance into post-if state it can never reach).  Anything weaker —
-- loops included (zero-iteration and break paths fall through) — means
-- execution can continue past the if with the restriction state unknown.
-- flowMode falsy (default): does the block TERMINATE THE FUNCTION on
-- every fall-through path? Strict last-statement contract; breaks are
-- NOT terminators — they exit loops, and clause-rollback semantics
-- depend on that distinction.
-- flowMode true: the round-10d reachability view — does this ONE-
-- STATEMENT wrapper's statement end flow in its own block? Breaks
-- count, loop-exit wrappers count, and loops whose exit is provably
-- never reached count. stmtEndsFlow (defined above) is the public
-- wrapper; walkStatements calls this directly because it sits at the
-- 60-upvalue cap and already captures this name.
bodyTerminates = function(stmtlist, flowMode)
    local body = type(stmtlist) == "table" and stmtlist.Body
    if type(body) ~= "table" or #body == 0 then return false end
    if flowMode then
        return stmtEndsFlowCore(body[#body])
    end
    local last = body[#body]
    if last.AstType == "ReturnStatement" then return true end
    if last.AstType == "CallStatement" then
        local expr = last.Expression
        if expr and expr.AstType == "CallExpr" then
            -- A chunk that rebinds `error` forfeits the terminator: the
            -- shadowed call may return normally (see fnErrorShadowed).
            return callTargetName(expr.Base) == "error"
                and not fnErrorShadowed
        end
        return false
    end
    if last.AstType == "IfStatement" and type(last.Clauses) == "table"
        and #last.Clauses > 0 then
        local hasElse = false
        for _, clause in ipairs(last.Clauses) do
            if not clause.Condition then hasElse = true end
            if not bodyTerminates(clause.Body) then return false end
        end
        return hasElse
    end
    if last.AstType == "DoStatement" then
        return bodyTerminates(last.Body)
    end
    return false
end

-- The flow-view core (round-10d follow-ups 5-9): one statement, one
-- answer — does it end flow in its own block on every path? Reachability
-- rules live here so they cannot drift across consumers:
--   * REACHABLE direct breaks only (follow-up 9): a break in dead code —
--     after a flow-ending statement in its block — never executes and
--     must not revive the post-loop position. Each statement is scanned
--     for breaks FIRST (a live break INSIDE an all-arms flow-ender still
--     counts: `if Y then break else return end`), then a flow-ender
--     stops the scan.
--   * blockEndsFlow is the reachability-aware twin of the last-statement
--     terminate view: a dead trailing break after `do return nil end`
--     must not mask a body that always returns.
stmtEndsFlowCore = function(stmt)
    local function blockHasDirectBreak(block)
        for _, s in ipairs(block or {}) do
            local st = s.AstType
            if st == "BreakStatement" then return true end
            if st == "IfStatement" then
                for _, clause in ipairs(s.Clauses or {}) do
                    if clause.Body
                        and blockHasDirectBreak(clause.Body.Body) then
                        return true
                    end
                end
            elseif st == "DoStatement" then
                if s.Body and blockHasDirectBreak(s.Body.Body) then
                    return true
                end
            end
            if st and stmtEndsFlowCore(s) then return false end
        end
        return false
    end
    local function blockEndsFlow(block)
        for _, s in ipairs(block or {}) do
            if s.AstType and stmtEndsFlowCore(s) then return true end
        end
        return false
    end
    local ty = stmt.AstType
    if ty == "ReturnStatement" or ty == "BreakStatement" then return true end
    if ty == "CallStatement" then
        return bodyTerminates({ Body = { stmt } })
    end
    -- if/do wrappers use blockEndsFlow, NOT a last-statement check
    -- (Codex catch #11): a dead trailing statement after the clause's
    -- flow-ender (`do return nil end; DoWork()`) must not mask it.
    if ty == "IfStatement" and type(stmt.Clauses) == "table"
        and #stmt.Clauses > 0 then
        local hasElse = false
        for _, clause in ipairs(stmt.Clauses) do
            if not clause.Condition then hasElse = true end
            if not blockEndsFlow(clause.Body and clause.Body.Body) then
                return false
            end
        end
        return hasElse
    end
    if ty == "DoStatement" then
        return blockEndsFlow(stmt.Body and stmt.Body.Body)
    end
    if ty == "RepeatStatement" then
        if blockHasDirectBreak(stmt.Body and stmt.Body.Body) then
            return false
        end
        -- No reachable break: any reachable flow-ender in the body is a
        -- function-terminator, and the body runs at least once.
        if blockEndsFlow(stmt.Body and stmt.Body.Body) then return true end
        local cond = stmt.Condition
        return type(cond) == "table" and cond.AstType == "BooleanExpr"
            and cond.Value == false
    end
    if ty == "WhileStatement" then
        local cond = stmt.Condition
        return type(cond) == "table" and cond.AstType == "BooleanExpr"
            and cond.Value == true
            and not blockHasDirectBreak(stmt.Body and stmt.Body.Body)
    end
    return false
end

-- File-scope aliases of precondition-guarded APIs, restriction gates and
-- their NAMESPACES (2026-07 round-4: guarded aliases, alias chains and
-- namespace aliases were invisible):
--   local GetAuras = C_UnitAuras.GetUnitAuras            → map
--   local Get = C_UnitAuras and C_UnitAuras.GetUnitAuras → map (guarded init)
--   local Also = GetAuras                                → map (chain hop)
--   local UA = C_UnitAuras                               → ns
--   local isSecret = C_Secrets.ShouldAurasBeSecret       → map (gate alias)
-- The walk is STATEMENT-ORDERED so chains resolve through earlier hops.
-- Scoping/shadowing are not modeled (file-scope union). For the
-- finding-EMITTING resolution that over-approximation only ADDs findings;
-- for gate protection it could SUPPRESS them, so aliases.binds records every
-- binding of every name (locals, assignments, function names, parameters,
-- for-variables) and M.analyze poisons any alias name with a conflicting
-- binding — poisoned names never grant protection (isGateName) and never
-- serve as chain hops (aliases.poisoned is the `blocked` set fed back in by
-- the fixpoint loop).
-- Canonical recognized form of a resolved name: the name itself, or the
-- `_G.`/`ns.`-stripped variant when the stripped form is the recognized one
-- (`_G` = real global table, `ns` = QUI suite namespace proxy). Returns nil
-- when no variant is recognized.
local function canonicalRecognized(n, registry)
    if not n then return nil end
    local candidates = { n }
    for _, pre in ipairs({ "_G.", "ns." }) do
        if n:sub(1, #pre) == pre then
            candidates[#candidates + 1] = n:sub(#pre + 1)
        end
    end
    for _, c in ipairs(candidates) do
        if registry:preconditionFlags(c)
            or registry:isRestrictionGate(c)
            or registry:isGuard(c)
            or registry:isElementSecretFunction(c)
            or registry.preconditionNamespaces[c] then
            return c
        end
    end
    return nil
end

local function collectPreconditionAliases(node, registry, aliases, visited)
    if type(node) ~= "table" or visited[node] then return end
    visited[node] = true
    local poisoned = aliases.poisoned or {}
    -- Record a binding of `name`: canonical string when the bound value is a
    -- recognized gate/API/namespace, false (conflict) otherwise or on any
    -- disagreement between bindings.
    local function recordBind(name, canonical)
        if not name then return end
        local binds = aliases.binds
        if binds[name] == nil then
            binds[name] = canonical or false
        elseif binds[name] ~= canonical then
            binds[name] = false
        end
    end
    -- Canonical name an init expression resolves to, unwrapping the guarded
    -- `A and A.f` / `A and A.f or fallback` idioms by scanning operands.
    local function resolveInit(init)
        if type(init) ~= "table" then return nil end
        local t = init.AstType
        if t == "Parentheses" then return resolveInit(init.Inner) end
        if t == "MemberExpr" or t == "VarExpr" then
            local name = callTargetName(init)
            if not name then return nil end
            -- A chain hop through a poisoned name is ambiguous — refuse it.
            local base = name:match("^([%w_]+)")
            if base and poisoned[base] then return nil end
            return resolveAliasedName(name, aliases)
        end
        if t == "BinopExpr" and (init.Op == "and" or init.Op == "or") then
            -- canonicalRecognized also accepts `_G.`/`ns.`-prefixed forms —
            -- `(ns.Helpers and ns.Helpers.IsSecretValue) or <fallback fn>`
            -- must resolve to the recognized dotted guard, not dissolve.
            local n = canonicalRecognized(resolveInit(init.Rhs), registry)
            if n then return n end
            n = canonicalRecognized(resolveInit(init.Lhs), registry)
            if n then return n end
        end
        return nil
    end
    local function harvest(vars, inits, nameOf)
        if type(vars) ~= "table" then return end
        inits = type(inits) == "table" and inits or {}
        for i, var in ipairs(vars) do
            local localName = nameOf(var)
            if localName then
                local resolved = resolveInit(inits[i])
                -- Normalize `_G.`/`ns.` prefixes (see canonicalRecognized) so
                -- cache idioms like `local issecretvalue = _G.issecretvalue`
                -- and `local nsHelpers = ns.Helpers` register canonically
                -- instead of recording unrecognized bindings (false) that
                -- revoke guard credit or drop the namespace alias.
                resolved = canonicalRecognized(resolved, registry) or resolved
                local canonical
                -- Registration stays PERMISSIVE even for poisoned names — the
                -- finding-emitting resolution may over-approximate; poisoning
                -- only blocks gate/guard protection and chain hops.
                if resolved and (registry:preconditionFlags(resolved)
                    or registry:isRestrictionGate(resolved)
                    or registry:isGuard(resolved)
                    or registry:isElementSecretFunction(resolved)) then
                    canonical = resolved
                    aliases.map[localName] = resolved
                elseif resolved and registry.preconditionNamespaces[resolved] then
                    canonical = resolved
                    aliases.ns[localName] = resolved
                end
                recordBind(localName, canonical)
            end
        end
    end
    if node.AstType == "Statlist" and type(node.Body) == "table" then
        for _, stmt in ipairs(node.Body) do
            collectPreconditionAliases(stmt, registry, aliases, visited)
        end
        return
    end
    if node.AstType == "LocalStatement" then
        harvest(node.LocalList, node.InitList, function(v) return v.Name end)
    elseif node.AstType == "AssignmentStatement" then
        harvest(node.Lhs, node.Rhs, function(v)
            return v.AstType == "VarExpr" and v.Name or nil
        end)
    elseif node.AstType == "Function" then
        -- Function names and parameters are bindings too (a local function or
        -- a parameter reusing an alias name makes that name ambiguous).
        if node.Name and node.Name.Name then recordBind(node.Name.Name, nil) end
        for _, arg in ipairs(node.Arguments or {}) do
            if arg.Name then recordBind(arg.Name, nil) end
        end
        collectPreconditionAliases(node.Body, registry, aliases, visited)
        return
    elseif node.AstType == "NumericForStatement" then
        if node.Variable and node.Variable.Name then
            recordBind(node.Variable.Name, nil)
        end
    elseif node.AstType == "GenericForStatement" then
        for _, v in ipairs(node.VariableList or {}) do
            if v.Name then recordBind(v.Name, nil) end
        end
    end
    for k, v in pairs(node) do
        if k ~= "Tokens" and type(v) == "table" then
            collectPreconditionAliases(v, registry, aliases, visited)
        end
    end
end

-- Binding scan for fnErrorShadowed (see its declaration).  Two layers:
--   * bare rebinds — locals, assignments to a bare name, function names and
--     parameters, numeric/generic for-variables (binder shapes mirror
--     collectPreconditionAliases);
--   * global-environment rebinds (round-8m, review) — `_G.error = f`,
--     `_G["error"] = f`, `rawset(_G, "error", f)`, the same through an
--     _G alias (`local g = _G; g.error = f`, alias chains fixpointed) or a
--     getfenv() result, a DYNAMIC env write (`_G[k] = f` — the key is
--     unknowable, so refuse), and any setfenv() call (the chunk env can be
--     replaced wholesale).
-- Bare rebinds use the chunk-wide name union (over-approximating SHADOWED
-- only refuses protection, never grants it); env-ness resolves on parser
-- VARIABLE IDENTITY (VarExpr.Variable + IsGlobal), so `local _G = {}` is a
-- plain table whose writes never count, while `local _G = _G` and other
-- aliases of the real global env do.  Non-env dotted writes (`M.error = f`,
-- a module logger) don't rebind the bare global and stay ignored.  Known
-- residue: an ALIASED rawset/setfenv (`local rs = rawset`) and env values
-- returned from calls (`local g = GetEnv()`) escape the match.
local function chunkShadowsError(ast)
    local shadowed = false
    local varInits = {}   -- {var=, init=} bindings, parser variable objects
    local envWrites = {}  -- {base=} member/index writes keyed "error"/dynamic
    -- Key an index/argument expression provably resolves to: the string
    -- itself for a string literal, nil for other literals (never "error"),
    -- "?" for anything dynamic.
    local function keyOf(idx)
        idx = stripParens(idx)
        if type(idx) ~= "table" then return nil end
        if idx.AstType == "StringExpr" then
            return stringLiteralValue(idx) or "?"
        end
        if idx.AstType == "NumberExpr" or idx.AstType == "BooleanExpr" then
            return nil
        end
        return "?"
    end
    local function recordEnvWrite(base, key)
        if key == "error" or key == "?" then
            envWrites[#envWrites + 1] = base
        end
    end
    local function walk(node, visited)
        if type(node) ~= "table" or visited[node] then return end
        visited[node] = true
        local t = node.AstType
        if t == "LocalStatement" then
            local inits = node.InitList or {}
            for i, v in ipairs(node.LocalList or {}) do
                -- LocalList entries ARE the parser variable objects.
                if v.Name == "error" then shadowed = true end
                varInits[#varInits + 1] = { var = v, init = inits[i] }
            end
        elseif t == "AssignmentStatement" then
            local rhs = node.Rhs or {}
            for i, v in ipairs(node.Lhs or {}) do
                if v.AstType == "VarExpr" then
                    if v.Name == "error" then shadowed = true end
                    if v.Variable then
                        varInits[#varInits + 1] = { var = v.Variable, init = rhs[i] }
                    end
                elseif v.AstType == "MemberExpr" then
                    if v.Ident and v.Ident.Data == "error" then
                        recordEnvWrite(v.Base, "error")
                    end
                elseif v.AstType == "IndexExpr" then
                    recordEnvWrite(v.Base, keyOf(v.Index))
                end
            end
        elseif t == "Function" then
            if node.Name then
                if node.Name.Name == "error" then shadowed = true end
                -- Environment function DECLARATIONS (`function _G.error()
                -- end`, dot or colon, directly or via an _G alias) are env
                -- writes like any other assignment.
                if node.Name.AstType == "MemberExpr" and node.Name.Ident
                    and node.Name.Ident.Data == "error" then
                    recordEnvWrite(node.Name.Base, "error")
                end
            end
            for _, arg in ipairs(node.Arguments or {}) do
                if arg.Name == "error" then shadowed = true end
            end
        elseif t == "NumericForStatement" then
            if node.Variable and node.Variable.Name == "error" then
                shadowed = true
            end
        elseif t == "GenericForStatement" then
            for _, v in ipairs(node.VariableList or {}) do
                if v.Name == "error" then shadowed = true end
            end
        elseif t == "CallExpr" or t == "StringCallExpr" or t == "TableCallExpr" then
            local name = callTargetName(node.Base)
            if name == "setfenv" then shadowed = true end
            if name == "rawset" and t == "CallExpr" then
                local args = node.Arguments or {}
                if args[1] then
                    -- Same env test as member writes, deferred to resolution.
                    local key = keyOf(args[2])
                    if key == "error" or key == "?" then
                        envWrites[#envWrites + 1] = args[1]
                    end
                end
            end
        end
        for k, v in pairs(node) do
            if k ~= "Tokens" and type(v) == "table" then
                walk(v, visited)
            end
        end
    end
    walk(ast, {})
    if shadowed then return true end
    if #envWrites == 0 then return false end
    -- Resolve which VARIABLES denote the global environment: the GLOBAL _G
    -- (variable identity, so a shadowing `local _G = {}` never counts), then
    -- fixpoint over the collected bindings so chains (`local g = _G;
    -- local h = g`) land too.  A variable EVER bound to the env counts —
    -- the union over-approximates, which only refuses protection.
    local envVars = {}
    local function isGetfenvCall(n)
        n = stripParens(n)
        return type(n) == "table"
            and (n.AstType == "CallExpr" or n.AstType == "StringCallExpr"
                or n.AstType == "TableCallExpr")
            and callTargetName(n.Base) == "getfenv"
    end
    local function isEnvBase(n)
        n = stripParens(n)
        if type(n) ~= "table" then return false end
        if n.AstType == "VarExpr" then
            local var = n.Variable
            if var then
                return envVars[var] == true
                    or (n.Name == "_G" and var.IsGlobal == true)
            end
            return n.Name == "_G" -- no identity info: conservative name match
        end
        return isGetfenvCall(n)
    end
    repeat
        local changed = false
        for _, b in ipairs(varInits) do
            if not envVars[b.var] and isEnvBase(b.init) then
                envVars[b.var] = true
                changed = true
            end
        end
    until not changed
    for _, base in ipairs(envWrites) do
        if isEnvBase(base) then return true end
    end
    return false
end

local preconditionScan

-- Ordered walk over a statement list. Dominance is deliberately narrow: the
-- `gated` state flips true for FOLLOWING statements only when an if-clause
-- whose condition is a POSITIVE gate (`if gate() then`) has a body that
-- unconditionally returns/errors — the authored bail idiom. A gate whose
-- result is ignored (`local _ = gate()`), inverted without a terminating
-- branch, or buried in an unmodeled expression proves nothing and no longer
-- protects later calls (2026-07 re-review: the old any-gate-in-statement
-- flip accepted all of those).
local function preconditionScanBody(stmts, registry, filePath, findings, gated, visited, aliases)
    if type(stmts) ~= "table" then return end
    -- Escape prepass (round-4 named-callback false negative; round-6 widened
    -- to returned and stored callbacks): a local function — `local function
    -- f` or `local f = function()` — whose NAME is later passed as a call
    -- argument (`f:SetScript("OnEvent", OnEvent)`), RETURNED, assigned
    -- anywhere (module export, table field, re-bind), or placed in a table
    -- constructor, escapes exactly like an inline closure — its body runs
    -- later under an unknown restriction state, so it must scan UNGATED
    -- regardless of gates above its definition. A name only ever used as a
    -- call BASE (`inner()`) stays synchronous and inherits normally.
    -- Cross-list escapes (defined here, passed elsewhere) are not modeled.
    local escapedFns
    do
        local defined
        for _, stmt in ipairs(stmts) do
            if stmt.AstType == "Function" and stmt.IsLocal
                and stmt.Name and stmt.Name.Name then
                defined = defined or {}
                defined[stmt.Name.Name] = true
            elseif stmt.AstType == "LocalStatement"
                and type(stmt.LocalList) == "table" then
                for i, v in ipairs(stmt.LocalList) do
                    local init = stmt.InitList and stmt.InitList[i]
                    if v.Name and type(init) == "table"
                        and init.AstType == "Function" then
                        defined = defined or {}
                        defined[v.Name] = true
                    end
                end
            end
        end
        if defined then
            local function mark(a)
                if type(a) == "table" and a.AstType == "VarExpr"
                    and defined[a.Name] then
                    escapedFns = escapedFns or {}
                    escapedFns[a.Name] = true
                end
            end
            local function findEscapes(n, seen)
                if type(n) ~= "table" or seen[n] then return end
                seen[n] = true
                local t = n.AstType
                if (t == "CallExpr" or t == "ReturnStatement")
                    and type(n.Arguments) == "table" then
                    for _, a in ipairs(n.Arguments) do mark(a) end
                elseif t == "AssignmentStatement" and type(n.Rhs) == "table" then
                    for _, a in ipairs(n.Rhs) do mark(a) end
                elseif t == "LocalStatement" and type(n.InitList) == "table" then
                    -- `local g = f` can be called synchronously, but tracking
                    -- that alias is out of scope — treat as an escape
                    -- (over-report direction).
                    for _, a in ipairs(n.InitList) do mark(a) end
                elseif t == "ConstructorExpr" and type(n.EntryList) == "table" then
                    for _, entry in ipairs(n.EntryList) do
                        if entry then mark(entry.Value) end
                    end
                end
                for k, v in pairs(n) do
                    if k ~= "Tokens" and type(v) == "table" then findEscapes(v, seen) end
                end
            end
            for _, stmt in ipairs(stmts) do findEscapes(stmt, {}) end
        end
    end
    for _, stmt in ipairs(stmts) do
        if stmt.AstType == "IfStatement" and type(stmt.Clauses) == "table" then
            local flip = false
            local soleGatePolarity, gateClauseCount = nil, 0
            for _, clause in ipairs(stmt.Clauses) do
                if clause.Condition then
                    local p = gateConditionPolarity(clause.Condition, registry, aliases)
                    if p then
                        gateClauseCount = gateClauseCount + 1
                        soleGatePolarity = p
                    end
                end
            end
            -- Dominance flip: ONLY the FIRST clause can prove it. An
            -- `elseif gate() then return end` is unsound — when an earlier
            -- clause's condition is true, the gate is never evaluated and
            -- that branch falls through with the restriction state unknown.
            -- Flip-safety additionally requires restrictedImpliesTrue (a
            -- restricted state cannot slip past the condition) plus a
            -- terminating body.
            do
                local first = stmt.Clauses[1]
                if first and first.Condition
                    and restrictedImpliesTrue(first.Condition, registry, aliases)
                    and bodyTerminates(first.Body) then
                    flip = true
                end
            end
            -- priorsProve: reaching clause k means every earlier condition
            -- was evaluated AND false. If ANY earlier condition is
            -- restricted-implies-true, its falsity proves the state was
            -- unrestricted at that evaluation — so clause k's condition AND
            -- body run only UNRESTRICTED. This protects `elseif`/`else`
            -- after an `if gate() then …` (round-6 false positive) and
            -- replaces the old sole-positive-gate else shortcut, which
            -- wrongly protected the else of compound conditions like
            -- `if gate() and ready then` — that else IS restricted-reachable
            -- via `ready == false` while gate() is true (round-6 false
            -- negative; restrictedImpliesTrue refuses arbitrary conjuncts).
            local priorsProve = false
            for _, clause in ipairs(stmt.Clauses) do
                local entryProven = priorsProve
                local scanGated
                if clause.Condition then
                    local pol = gateConditionPolarity(clause.Condition, registry, aliases)
                    if entryProven then
                        -- Every earlier clause would have caught a restricted
                        -- state — this clause is unrestricted-only.
                        scanGated = true
                    elseif pol == "negative" then
                        -- Branch runs only when UNRESTRICTED.
                        scanGated = true
                    elseif pol == "positive" then
                        -- Branch runs only when RESTRICTED: a guarded API
                        -- call here is a GUARANTEED hard error — scan
                        -- ungated so it flags even under an outer gate
                        -- (the gate was just re-consulted and came back
                        -- restricted).
                        scanGated = false
                    elseif restrictedImpliesTrue(clause.Condition, registry, aliases) then
                        -- Unmodeled polarity but restricted GUARANTEES entry
                        -- (`gate() or fallback`): the body is
                        -- restricted-REACHABLE, so a guarded call inside it
                        -- can hard-error — scan ungated.
                        scanGated = false
                    else
                        -- No/unmodeled gate (`gate() ~= nil`, gate under a
                        -- comparison): UNKNOWN conditions never grant
                        -- protection — inherit (2026-07 round-4; the old
                        -- gate-anywhere-in-condition fallback suppressed
                        -- real findings).
                        scanGated = gated
                    end
                    preconditionScan(clause.Condition, registry, filePath,
                        findings, gated or entryProven, visited, aliases)
                    priorsProve = priorsProve
                        or (restrictedImpliesTrue(clause.Condition, registry, aliases) ~= nil)
                else
                    -- else clause: runs when every condition was false.
                    if entryProven then
                        scanGated = true
                    elseif gateClauseCount == 1 and soleGatePolarity == "negative" then
                        -- Sole negative gate (`if not gate() then A else B`):
                        -- B is restricted-reachable — scan ungated.
                        scanGated = false
                    else
                        scanGated = gated
                    end
                end
                preconditionScanBody(clause.Body and clause.Body.Body,
                    registry, filePath, findings, scanGated, visited, aliases)
            end
            if flip then gated = true end
        elseif stmt.AstType == "Function" and stmt.IsLocal
            and stmt.Name and stmt.Name.Name
            and escapedFns and escapedFns[stmt.Name.Name] then
            -- Escaped named callback (see the prepass above): its body must
            -- not inherit a definition-time gate.
            preconditionScan(stmt, registry, filePath, findings, false, visited, aliases)
        elseif stmt.AstType == "LocalStatement" and escapedFns
            and type(stmt.LocalList) == "table" then
            -- `local f = function()` whose name escapes: the closure body
            -- scans UNGATED first (visited then skips it in the full-stmt
            -- scan below, which covers the remaining inits normally).
            for i, v in ipairs(stmt.LocalList) do
                local init = stmt.InitList and stmt.InitList[i]
                if type(init) == "table" and init.AstType == "Function"
                    and v.Name and escapedFns[v.Name] then
                    preconditionScan(init, registry, filePath, findings, false, visited, aliases)
                end
            end
            preconditionScan(stmt, registry, filePath, findings, gated, visited, aliases)
        else
            preconditionScan(stmt, registry, filePath, findings, gated, visited, aliases)
        end
    end
end

function preconditionScan(node, registry, filePath, findings, gated, visited, aliases)
    if type(node) ~= "table" or visited[node] then return end
    visited[node] = true

    if node.AstType == "Function" then
        -- New gate scope: the body walks in statement order, seeded with the
        -- lexically-inherited state at the definition point. Parameters
        -- cannot contain calls in Lua 5.1, so only the body needs scanning.
        preconditionScanBody(node.Body and node.Body.Body, registry, filePath,
            findings, gated, visited, aliases)
        return
    end

    if node.AstType == "Statlist" then
        -- Every nested block (while/for/do bodies) walks in statement order
        -- too, so gate-below-call inside a block is caught the same way as
        -- at function top level. (IfStatement clause bodies are routed
        -- through preconditionScanBody's polarity handling and never reach
        -- here — their Statlist nodes are already in `visited`.)
        preconditionScanBody(node.Body, registry, filePath, findings, gated, visited, aliases)
        return
    end

    if node.AstType == "ReturnStatement" then
        -- A RETURNED closure runs in the caller under an unknown restriction
        -- state — scan ungated, same rule as closures passed to arbitrary
        -- calls (round-6: returned callbacks inherited the definition-time
        -- gate).
        if type(node.Arguments) == "table" then
            for _, a in ipairs(node.Arguments) do
                local g = gated
                if type(a) == "table" and a.AstType == "Function" then g = false end
                preconditionScan(a, registry, filePath, findings, g, visited, aliases)
            end
        end
        return
    end

    if node.AstType == "ConstructorExpr" then
        -- TABLE-STORED closures escape (callback/handler tables run their
        -- entries later via unknown paths) — scan ungated.
        if type(node.EntryList) == "table" then
            for _, entry in ipairs(node.EntryList) do
                if entry then
                    if type(entry.Key) == "table" then
                        preconditionScan(entry.Key, registry, filePath, findings, gated, visited, aliases)
                    end
                    local v = entry.Value
                    local g = gated
                    if type(v) == "table" and v.AstType == "Function" then g = false end
                    preconditionScan(v, registry, filePath, findings, g, visited, aliases)
                end
            end
        end
        return
    end

    if node.AstType == "AssignmentStatement" then
        -- STORED closures escape (module exports, table fields, upvalue
        -- re-binds): `M.handler = function() … end` runs later under an
        -- unknown restriction state — scan ungated.
        if type(node.Lhs) == "table" then
            for _, l in ipairs(node.Lhs) do
                preconditionScan(l, registry, filePath, findings, gated, visited, aliases)
            end
        end
        if type(node.Rhs) == "table" then
            for _, r in ipairs(node.Rhs) do
                local g = gated
                if type(r) == "table" and r.AstType == "Function" then g = false end
                preconditionScan(r, registry, filePath, findings, g, visited, aliases)
            end
        end
        return
    end

    if node.AstType == "CallExpr" then
        local name = callTargetName(node.Base)
        if name == "pcall" or name == "xpcall" then
            -- Only argument 1 is protected, and only when it is a CLOSURE:
            -- pcall(function() API() end) runs the body under protection,
            -- while pcall(API(...)) evaluates the call BEFORE pcall takes
            -- over and must flag. A function REFERENCE argument is not a
            -- CallExpr so it never flags. The base, every other argument,
            -- and xpcall's handler evaluate/run unprotected — inherited
            -- state.
            local args = node.Arguments
            if type(args) == "table" then
                for i = 1, #args do
                    local argGated = gated
                    if i == 1 and args[i].AstType == "Function" then
                        argGated = true
                    end
                    preconditionScan(args[i], registry, filePath, findings,
                        argGated, visited, aliases)
                end
            end
            preconditionScan(node.Base, registry, filePath, findings, gated, visited, aliases)
            return
        end
        if name and not gated then
            -- Resolve file-local aliases: direct (`local Get =
            -- C_UnitAuras.GetUnitAuras; Get()`) and namespace (`local UA =
            -- C_UnitAuras; UA.GetUnitAuras()`).
            local canonical = name
            if not registry:preconditionFlags(name) then
                canonical = resolveAliasedName(name, aliases)
            end
            local flags = registry:preconditionFlags(canonical)
            if flags then
                local flagText = type(flags) == "table" and table.concat(flags, ",")
                    or "precondition-guarded"
                findings[#findings + 1] = {
                    file = filePath, line = nodeLine(node) or 0, col = 1,
                    severity = "review",
                    source_function = canonical,
                    sink = "<precondition>",
                    message = flagText .. " API called without a restriction gate or pcall — hard-errors under encounter/M+/PvP restrictions",
                    suppressed = false, suppression_reason = nil,
                }
            end
        end
        -- A CLOSURE passed to an arbitrary call ESCAPES: it can run later
        -- (timers, hooks, event registration) under a different restriction
        -- state, so a gate at the registration site proves nothing for its
        -- body — escaping closures scan UNGATED (2026-07 round-3
        -- later-callback false negative). Everything else inherits. The
        -- pcall branch above already returned, so this never demotes a
        -- protected pcall closure.
        local args = node.Arguments
        if type(args) == "table" then
            for i = 1, #args do
                local argGated = gated
                if type(args[i]) == "table" and args[i].AstType == "Function" then
                    argGated = false
                end
                preconditionScan(args[i], registry, filePath, findings,
                    argGated, visited, aliases)
            end
        end
        preconditionScan(node.Base, registry, filePath, findings, gated, visited, aliases)
        return
    end

    for k, v in pairs(node) do
        if k ~= "Tokens" then
            preconditionScan(v, registry, filePath, findings, gated, visited, aliases)
        end
    end
end

-- Small, lexical same-file summaries bridge straight-line wrapper boundaries
-- without pretending to be a whole-program call graph. A summarized function
-- records which parameters (or a direct source) may reach its return and which
-- parameters may reach a secret-unsafe operation. Branch/loop-heavy helpers
-- remain with the existing intraprocedural analysis.
--
-- Function VALUE timelines are separate from function-body summaries. They
-- follow parser binder identity through lexical blocks, aliases and rebinds;
-- call-time resolution then composes nested wrappers against the value visible
-- when the outer wrapper runs.
local function collectIntraFileFunctionSummaries(ast, registry)
    -- A function binding is a VALUE timeline, not one summary plus a textual
    -- invalidation cutoff.  That distinction is observable in ordinary Lua:
    -- `local Alias = Helper` captures the old closure, while a call to Helper
    -- from inside another closure resolves Helper when the OUTER closure runs.
    -- Keep every identity keyed by the parser's lexical binder object.
    local CHUNK_OWNER, UNKNOWN_VALUE = {}, {}
    local model = {
        chunkOwner = CHUNK_OWNER,
        unknownValue = UNKNOWN_VALUE,
        binderOwners = {},
        nodeOwners = {},
        summariesByNode = {},
        events = {},
    }

    local function ownerOf(binder)
        return model.binderOwners[binder] or CHUNK_OWNER
    end

    local function registerTree(node, owner, seen)
        if type(node) ~= "table" or seen[node] then return end
        -- Parser binder records point back into their Scope graph; they are
        -- identities, not AST containers.
        if not node.AstType and node.Scope and type(node.Name) == "string" then
            return
        end
        seen[node] = true
        local t = node.AstType
        if t then model.nodeOwners[node] = owner end

        if t == "Function" then
            local summary = {
                node = node,
                declarationOwner = owner,
                paramBinders = {},
            }
            model.summariesByNode[node] = summary
            if node.IsLocal and type(node.Name) == "table"
                and node.Name.Name and not node.Name.AstType then
                model.binderOwners[node.Name] = owner
            end
            for index, parameter in ipairs(node.Arguments or {}) do
                if parameter.Name then
                    model.binderOwners[parameter] = node
                    summary.paramBinders[parameter] = index
                end
            end
            registerTree(node.Body, node, seen)
            if type(node.Name) == "table" and node.Name.AstType then
                registerTree(node.Name, owner, seen)
            end
            return
        elseif t == "LocalStatement" then
            for _, binder in ipairs(node.LocalList or {}) do
                if binder.Name then model.binderOwners[binder] = owner end
            end
        elseif t == "NumericForStatement" and node.Variable then
            model.binderOwners[node.Variable] = owner
        elseif t == "GenericForStatement" then
            for _, binder in ipairs(node.VariableList or {}) do
                model.binderOwners[binder] = owner
            end
        end

        for key, child in pairs(node) do
            if key ~= "Tokens" and key ~= "Variable" and key ~= "Scope"
                and not (t == "Function" and key == "Name") then
                if type(child) == "table" then
                    if child.AstType then
                        registerTree(child, owner, seen)
                    else
                        for _, item in ipairs(child) do
                            if type(item) == "table" and item.AstType then
                                registerTree(item, owner, seen)
                            elseif type(item) == "table" then
                                -- If-clause and constructor-entry wrappers
                                -- have no AstType but contain real AST nodes.
                                registerTree(item, owner, seen)
                            end
                        end
                        -- Non-array wrappers (for example an if clause).
                        for wrapperKey, item in pairs(child) do
                            if type(wrapperKey) ~= "number"
                                and type(item) == "table" then
                                registerTree(item, owner, seen)
                            end
                        end
                    end
                end
            end
        end
    end
    registerTree(ast, CHUNK_OWNER, {})

    local function pointFor(node)
        local line, char = nodeLocation(node)
        return { line = line, char = char }
    end

    local endPointCache = {}
    local function endPoint(node, visiting)
        if type(node) ~= "table" then return { line = 0, char = 0 } end
        if not node.AstType and node.Scope and type(node.Name) == "string" then
            return { line = 0, char = 0 }
        end
        local cached = endPointCache[node]
        if cached then return cached end
        if visiting and visiting[node] then return { line = 0, char = 0 } end
        visiting = visiting or {}
        visiting[node] = true
        local best = pointFor(node)
        for _, token in ipairs(node.Tokens or {}) do
            local line, char = token.Line or 0, token.Char or 0
            if line > best.line or (line == best.line and char > best.char) then
                best = { line = line, char = char }
            end
        end
        for key, child in pairs(node) do
            if key ~= "Variable" and key ~= "Scope" and key ~= "Tokens"
                and type(child) == "table" then
                local function include(item)
                    if type(item) ~= "table" then return end
                    local p = endPoint(item, visiting)
                    if p.line > best.line
                        or (p.line == best.line and p.char > best.char) then
                        best = { line = p.line, char = p.char }
                    end
                end
                if child.AstType then
                    include(child)
                else
                    for _, item in pairs(child) do include(item) end
                end
            end
        end
        visiting[node] = nil
        endPointCache[node] = best
        return best
    end

    local function pointBefore(left, right)
        if not left or not right then return false end
        return left.line < right.line
            or (left.line == right.line and left.char < right.char)
    end

    local function stripAssignmentParens(expr)
        while type(expr) == "table" and expr.AstType == "Parentheses" do
            expr = expr.Inner
        end
        return expr
    end

    local function valueEvent(expr)
        expr = stripAssignmentParens(expr)
        if type(expr) ~= "table" then
            return { kind = "unknown" }
        elseif expr.AstType == "Function" then
            return {
                kind = "function",
                summary = model.summariesByNode[expr],
            }
        elseif expr.AstType == "VarExpr" and expr.Variable then
            return {
                kind = "alias",
                binder = expr.Variable,
                capturePoint = pointFor(expr),
            }
        end
        return { kind = "unknown" }
    end

    local function addEvent(binder, node, owner, mode, value)
        if not binder then return end
        local list = model.events[binder]
        if not list then
            list = {}
            model.events[binder] = list
        end
        list[#list + 1] = {
            node = node,
            owner = owner,
            mode = mode,
            value = value,
            endPoint = endPoint(node),
        }
    end

    local function collectListEvents(stmts, owner, definite)
        for _, stmt in ipairs(stmts or {}) do
            local t = stmt.AstType
            if t == "Function" then
                local summary = model.summariesByNode[stmt]
                if stmt.IsLocal and type(stmt.Name) == "table"
                    and stmt.Name.Name and not stmt.Name.AstType then
                    -- A local declaration is the binder's first value on every
                    -- path where that binder is in scope.
                    addEvent(stmt.Name, stmt, owner, "set", {
                        kind = "function",
                        summary = summary,
                    })
                else
                    local lhs = stripAssignmentParens(stmt.Name)
                    local binder = lhs and lhs.AstType == "VarExpr"
                        and lhs.Variable
                    if binder and ownerOf(binder) == owner then
                        addEvent(binder, stmt, owner,
                            definite and "set" or "may", {
                                kind = "function",
                                summary = summary,
                            })
                    end
                end
            elseif t == "LocalStatement" then
                for index, binder in ipairs(stmt.LocalList or {}) do
                    addEvent(binder, stmt, owner, "set",
                        valueEvent(stmt.InitList and stmt.InitList[index]))
                end
            elseif t == "AssignmentStatement" then
                for index, rawLhs in ipairs(stmt.Lhs or {}) do
                    local lhs = stripAssignmentParens(rawLhs)
                    local binder = lhs and lhs.AstType == "VarExpr"
                        and lhs.Variable
                    -- A closure assigning an upvalue does not execute merely
                    -- because the closure was defined. Its caller is outside
                    -- this compact value timeline, so retain the outer value.
                    if binder and ownerOf(binder) == owner then
                        addEvent(binder, stmt, owner,
                            definite and "set" or "may",
                            valueEvent(stmt.Rhs and stmt.Rhs[index]))
                    end
                end
            elseif t == "DoStatement" then
                -- `do ... end` executes once when reached, so its assignments
                -- are deterministic value events just like adjacent chunk
                -- statements.
                collectListEvents(stmt.Body and stmt.Body.Body, owner, definite)
            elseif t == "IfStatement" then
                local armValues, hasElse, supported = {}, false, true
                local function guaranteedArmValues(armStmts)
                    local guaranteed = {}
                    for _, armStmt in ipairs(armStmts or {}) do
                        local armType = armStmt.AstType
                        if armType == "Function" then
                            local lhs = armStmt.IsLocal and armStmt.Name
                                or stripAssignmentParens(armStmt.Name)
                            local binder = lhs and (
                                (lhs.Name and not lhs.AstType and lhs)
                                or (lhs.AstType == "VarExpr" and lhs.Variable))
                            if binder and ownerOf(binder) == owner then
                                guaranteed[binder] = {
                                    kind = "function",
                                    summary = model.summariesByNode[armStmt],
                                }
                            end
                        elseif armType == "AssignmentStatement" then
                            for index, rawLhs in ipairs(armStmt.Lhs or {}) do
                                local lhs = stripAssignmentParens(rawLhs)
                                local binder = lhs
                                    and lhs.AstType == "VarExpr"
                                    and lhs.Variable
                                if binder and ownerOf(binder) == owner then
                                    guaranteed[binder] = valueEvent(
                                        armStmt.Rhs and armStmt.Rhs[index])
                                end
                            end
                        elseif armType == "DoStatement" then
                            local nested, nestedSupported =
                                guaranteedArmValues(
                                    armStmt.Body and armStmt.Body.Body)
                            if not nestedSupported then return nil, false end
                            for binder, value in pairs(nested) do
                                guaranteed[binder] = value
                            end
                        elseif armType == "IfStatement"
                            or armType == "WhileStatement"
                            or armType == "RepeatStatement"
                            or armType == "NumericForStatement"
                            or armType == "GenericForStatement"
                            or armType == "ReturnStatement"
                            or armType == "BreakStatement" then
                            -- Keep the compact event proof intentionally
                            -- strict: nested control flow needs its own
                            -- exit-path analysis.
                            return nil, false
                        end
                    end
                    return guaranteed, true
                end
                for _, clause in ipairs(stmt.Clauses or {}) do
                    collectListEvents(clause.Body and clause.Body.Body,
                        owner, false)
                    if not clause.Condition then hasElse = true end
                    local values, armSupported = guaranteedArmValues(
                        clause.Body and clause.Body.Body)
                    if not armSupported then supported = false end
                    armValues[#armValues + 1] = values or {}
                end
                -- With an else arm, a binder assigned on every supported arm
                -- cannot retain its pre-if closure. Install the union of the
                -- selected arm values as one deterministic post-if event.
                if hasElse and supported and #armValues > 0 then
                    for binder in pairs(armValues[1]) do
                        local alternatives, everywhere = {}, true
                        for _, values in ipairs(armValues) do
                            if not values[binder] then
                                everywhere = false
                                break
                            end
                            alternatives[#alternatives + 1] = values[binder]
                        end
                        if everywhere then
                            addEvent(binder, stmt, owner, "set", {
                                kind = "alternatives",
                                values = alternatives,
                            })
                        end
                    end
                end
            elseif t == "WhileStatement" or t == "RepeatStatement"
                or t == "NumericForStatement"
                or t == "GenericForStatement" then
                collectListEvents(stmt.Body and stmt.Body.Body, owner, false)
            end
        end
    end
    collectListEvents(ast.Body, CHUNK_OWNER, true)
    for node in pairs(model.summariesByNode) do
        collectListEvents(node.Body and node.Body.Body, node, true)
    end

    local function listIsStraightLine(stmts)
        for _, stmt in ipairs(stmts or {}) do
            local t = stmt.AstType
            if t == "IfStatement" or t == "WhileStatement"
                or t == "RepeatStatement" or t == "NumericForStatement"
                or t == "GenericForStatement" then
                return false
            elseif t == "DoStatement"
                and not listIsStraightLine(stmt.Body and stmt.Body.Body) then
                return false
            end
            -- A nested function declaration only binds a value here; its body
            -- is summarized in its own execution context.
        end
        return true
    end
    for _, summary in pairs(model.summariesByNode) do
        summary.usable =
            listIsStraightLine(summary.node.Body and summary.node.Body.Body)
    end

    local function newDep()
        return { source = false, params = {} }
    end
    local function copyDep(dep)
        local copy = newDep()
        if dep then
            copy.source = dep.source == true
            for index in pairs(dep.params or {}) do copy.params[index] = true end
        end
        return copy
    end
    local function unionInto(target, source)
        if not source then return target end
        if source.source then target.source = true end
        for index in pairs(source.params or {}) do target.params[index] = true end
        return target
    end
    local function cloneEnv(env)
        local copy = {}
        for binder, dep in pairs(env) do copy[binder] = copyDep(dep) end
        return copy
    end
    local function depEqual(left, right)
        if (left and left.source or false)
            ~= (right and right.source or false) then
            return false
        end
        for index in pairs(left and left.params or {}) do
            if not (right and right.params and right.params[index]) then
                return false
            end
        end
        for index in pairs(right and right.params or {}) do
            if not (left and left.params and left.params[index]) then
                return false
            end
        end
        return true
    end
    local function envEqual(left, right)
        for binder, dep in pairs(left) do
            if not depEqual(dep, right[binder]) then return false end
        end
        for binder, dep in pairs(right) do
            if not depEqual(dep, left[binder]) then return false end
        end
        return true
    end
    local function mergeEnvs(envs)
        local merged = {}
        for _, env in ipairs(envs) do
            for binder, dep in pairs(env) do
                merged[binder] =
                    unionInto(merged[binder] or newDep(), dep)
            end
        end
        return merged
    end
    local function newEffects()
        return {
            returnSource = false,
            returnParams = {},
            sinkParams = {},
        }
    end
    local function unionEffects(target, source)
        if source.returnSource then target.returnSource = true end
        for index in pairs(source.returnParams or {}) do
            target.returnParams[index] = true
        end
        for index in pairs(source.sinkParams or {}) do
            target.sinkParams[index] = true
        end
        return target
    end
    local function cloneTimes(times)
        local copy = {}
        for owner, point in pairs(times or {}) do copy[owner] = point end
        return copy
    end

    local resolveBinderEffects
    local function resolveValues(binder, times, fallbackPoint, resolving)
        local owner = ownerOf(binder)
        local time = times[owner] or fallbackPoint
        local events = model.events[binder]
        if not events or not time then return {}, false end
        if resolving[binder] then return { [UNKNOWN_VALUE] = true }, true end
        resolving[binder] = true
        local values, sawEvent = {}, false
        for _, event in ipairs(events) do
            if event.owner == owner and pointBefore(event.endPoint, time) then
                local eventValues = {}
                local value = event.value
                local function addValue(eventValue)
                    if eventValue.kind == "function"
                        and eventValue.summary then
                        eventValues[eventValue.summary] = true
                    elseif eventValue.kind == "alias"
                        and eventValue.binder then
                        local captureTimes = cloneTimes(times)
                        local targetOwner = ownerOf(eventValue.binder)
                        if targetOwner == event.owner then
                            captureTimes[targetOwner] =
                                eventValue.capturePoint
                        end
                        -- `Helper = Helper` snapshots the pre-assignment
                        -- value. The capture point is strictly before this
                        -- event's end, so a same-binder recursive lookup
                        -- decreases in source order and terminates.
                        local selfAlias = eventValue.binder == binder
                        if selfAlias then resolving[binder] = nil end
                        local targetValues, targetSaw = resolveValues(
                            eventValue.binder, captureTimes,
                            eventValue.capturePoint, resolving)
                        if selfAlias then resolving[binder] = true end
                        if targetSaw then
                            for target in pairs(targetValues) do
                                eventValues[target] = true
                            end
                        else
                            eventValues[UNKNOWN_VALUE] = true
                        end
                    elseif eventValue.kind == "alternatives" then
                        for _, alternative in ipairs(
                                eventValue.values or {}) do
                            addValue(alternative)
                        end
                    else
                        eventValues[UNKNOWN_VALUE] = true
                    end
                end
                addValue(value)
                if event.mode == "set" then values = {} end
                for valueSummary in pairs(eventValues) do
                    values[valueSummary] = true
                end
                sawEvent = true
            end
        end
        resolving[binder] = nil
        return values, sawEvent
    end

    local function analyzeSummary(summary, times, stack, inheritedFunctions)
        local effects = newEffects()
        if not summary.usable or stack[summary] then return effects end
        stack[summary] = true
        local returnDep = newDep()
        local sinkParams, safeParams = {}, {}
        local env = {}
        -- Per-invocation function values model deterministic assignments made
        -- while this wrapper is actually running. In particular, rebinding an
        -- upvalue and then calling it in the same wrapper must override the
        -- chunk value visible at wrapper entry without pretending that merely
        -- DEFINING the wrapper performed the assignment.
        local runtimeFunctionValues = {}
        for binder, values in pairs(inheritedFunctions or {}) do
            local copied = {}
            for value in pairs(values) do copied[value] = true end
            runtimeFunctionValues[binder] = copied
        end
        for binder, index in pairs(summary.paramBinders) do
            env[binder] = { source = false, params = { [index] = true } }
        end

        local evalExpr
        local walkList
        local function markSink(dep)
            for index in pairs(dep and dep.params or {}) do
                if not safeParams[index] then sinkParams[index] = true end
            end
        end
        local function copyFunctionValues(values)
            local copy = {}
            for value in pairs(values or {}) do copy[value] = true end
            return copy
        end
        local function functionValuesForExpr(expr)
            expr = stripAssignmentParens(expr)
            if type(expr) ~= "table" then
                return { [UNKNOWN_VALUE] = true }
            elseif expr.AstType == "Function" then
                local valueSummary = model.summariesByNode[expr]
                return valueSummary and { [valueSummary] = true }
                    or { [UNKNOWN_VALUE] = true }
            elseif expr.AstType == "VarExpr" and expr.Variable then
                local runtime = runtimeFunctionValues[expr.Variable]
                if runtime then return copyFunctionValues(runtime) end
                local lookupTimes = cloneTimes(times)
                lookupTimes[summary.node] = pointFor(expr)
                local values, resolved = resolveValues(
                    expr.Variable, lookupTimes, pointFor(expr), {})
                if resolved then return copyFunctionValues(values) end
            end
            return { [UNKNOWN_VALUE] = true }
        end
        local function effectsForFunctionValues(values, callTimes)
            local valueEffects = newEffects()
            for value in pairs(values or {}) do
                if value ~= UNKNOWN_VALUE then
                    unionEffects(valueEffects,
                        analyzeSummary(value, callTimes, stack,
                            runtimeFunctionValues))
                end
            end
            return valueEffects
        end
        evalExpr = function(expr, current)
            if type(expr) ~= "table" then return newDep() end
            local t = expr.AstType
            if t == "Parentheses" then return evalExpr(expr.Inner, current) end
            if t == "VarExpr" then
                return copyDep(current[expr.Variable])
            end
            if t == "DotsExpr" or t == "Function" then return newDep() end
            if t == "BinopExpr" then
                local dep = unionInto(evalExpr(expr.Lhs, current),
                    evalExpr(expr.Rhs, current))
                markSink(dep)
                if expr.Op == "and" or expr.Op == "or" then return dep end
                return newDep()
            end
            if t == "UnopExpr" then
                local dep = evalExpr(expr.Rhs, current)
                markSink(dep)
                return newDep()
            end
            if t == "MemberExpr" then
                return evalExpr(expr.Base, current)
            end
            if t == "IndexExpr" then
                local base = evalExpr(expr.Base, current)
                markSink(evalExpr(expr.Index, current))
                return base
            end
            if t == "ConstructorExpr" then
                local dep = newDep()
                for _, entry in ipairs(expr.EntryList or {}) do
                    if entry.Key then markSink(evalExpr(entry.Key, current)) end
                    unionInto(dep, evalExpr(entry.Value, current))
                end
                return dep
            end
            if t == "CallExpr" or t == "StringCallExpr"
                or t == "TableCallExpr" then
                local args = {}
                for index, arg in ipairs(expr.Arguments or {}) do
                    args[index] = evalExpr(arg, current)
                end
                local name, kind = callTargetName(expr.Base)
                if name and registry:isSource(name) then
                    local dep = newDep()
                    dep.source = true
                    return dep
                end
                local calleeBinder = expr.Base
                    and expr.Base.AstType == "VarExpr"
                    and expr.Base.Variable
                if calleeBinder then
                    local callTimes = cloneTimes(times)
                    callTimes[summary.node] = pointFor(expr)
                    local runtimeValues =
                        runtimeFunctionValues[calleeBinder]
                    local calleeEffects, resolved
                    if runtimeValues then
                        calleeEffects = effectsForFunctionValues(
                            runtimeValues, callTimes)
                        resolved = true
                    else
                        calleeEffects, resolved = resolveBinderEffects(
                            calleeBinder, callTimes, pointFor(expr), stack,
                            runtimeFunctionValues)
                    end
                    if resolved then
                        for index in pairs(calleeEffects.sinkParams) do
                            markSink(args[index])
                        end
                        local dep = newDep()
                        dep.source = calleeEffects.returnSource == true
                        for index in pairs(calleeEffects.returnParams) do
                            unionInto(dep, args[index])
                        end
                        return dep
                    end
                end
                local safe = name and (
                    (kind == "method"
                        and registry:isSafeSinkMethod(
                            getMethodNameFromQualified(name)))
                    or (kind == "function"
                        and registry:isSafeSinkFunction(name)))
                if name and UNSAFE_BUILTIN_FUNCTIONS[name] and not safe then
                    for _, dep in ipairs(args) do markSink(dep) end
                end
                if name and registry:isSecretReturning(name) then
                    local dep = newDep()
                    dep.source = true
                    return dep
                end
                return newDep()
            end
            return newDep()
        end

        walkList = function(stmts, current, allowFallthroughProofs)
            for _, stmt in ipairs(stmts or {}) do
                local t = stmt.AstType
                if t == "LocalStatement" then
                    local rhsDeps, rhsFunctions = {}, {}
                    for index, rhs in ipairs(stmt.InitList or {}) do
                        rhsDeps[index] = evalExpr(rhs, current)
                        rhsFunctions[index] = functionValuesForExpr(rhs)
                    end
                    for index, binder in ipairs(stmt.LocalList or {}) do
                        current[binder] =
                            copyDep(rhsDeps[index] or newDep())
                        runtimeFunctionValues[binder] =
                            rhsFunctions[index]
                            or { [UNKNOWN_VALUE] = true }
                    end
                elseif t == "AssignmentStatement" then
                    local rhsDeps, rhsFunctions = {}, {}
                    for index, rhs in ipairs(stmt.Rhs or {}) do
                        rhsDeps[index] = evalExpr(rhs, current)
                        rhsFunctions[index] = functionValuesForExpr(rhs)
                    end
                    for index, rawLhs in ipairs(stmt.Lhs or {}) do
                        local lhs = stripAssignmentParens(rawLhs)
                        if lhs and lhs.AstType == "VarExpr" and lhs.Variable then
                            current[lhs.Variable] =
                                copyDep(rhsDeps[index] or newDep())
                            runtimeFunctionValues[lhs.Variable] =
                                rhsFunctions[index]
                                or { [UNKNOWN_VALUE] = true }
                        elseif lhs and lhs.AstType == "IndexExpr" then
                            markSink(evalExpr(lhs.Index, current))
                        end
                    end
                elseif t == "Function" then
                    local lhs =
                        (stmt.IsLocal and type(stmt.Name) == "table"
                            and stmt.Name.Name and not stmt.Name.AstType
                            and stmt.Name)
                        or stripAssignmentParens(stmt.Name)
                    local binder = lhs and (
                        (lhs.Name and not lhs.AstType and lhs)
                        or (lhs.AstType == "VarExpr" and lhs.Variable))
                    local valueSummary = model.summariesByNode[stmt]
                    if binder then
                        runtimeFunctionValues[binder] =
                            valueSummary and { [valueSummary] = true }
                            or { [UNKNOWN_VALUE] = true }
                    end
                elseif t == "IfStatement" then
                    local exits, hasElse = {}, false
                    for _, clause in ipairs(stmt.Clauses or {}) do
                        if clause.Condition then
                            markSink(evalExpr(clause.Condition, current))
                        else
                            hasElse = true
                        end
                        exits[#exits + 1] = walkList(
                            clause.Body and clause.Body.Body,
                            cloneEnv(current), false)
                    end
                    if not hasElse then
                        exits[#exits + 1] = cloneEnv(current)
                    end
                    current = mergeEnvs(exits)
                    local first = stmt.Clauses and stmt.Clauses[1]
                    local guard = first and first.Condition
                        and analyzeGuard(first.Condition, registry)
                    if allowFallthroughProofs
                        and guard and guard.kind == "untaint-else"
                        and bodyTerminates(first.Body) then
                        for _, localName in ipairs(guard.locals or {}) do
                            for binder, dep in pairs(current) do
                                if binder.Name == localName then
                                    for index in pairs(dep.params or {}) do
                                        safeParams[index] = true
                                    end
                                end
                            end
                        end
                    end
                elseif t == "DoStatement" then
                    current = walkList(stmt.Body and stmt.Body.Body,
                        cloneEnv(current), allowFallthroughProofs)
                elseif t == "WhileStatement" or t == "RepeatStatement"
                    or t == "NumericForStatement"
                    or t == "GenericForStatement" then
                    if stmt.Condition then
                        markSink(evalExpr(stmt.Condition, current))
                    end
                    if t == "NumericForStatement" then
                        markSink(evalExpr(stmt.Start, current))
                        markSink(evalExpr(stmt.End, current))
                        markSink(evalExpr(stmt.Step, current))
                    elseif t == "GenericForStatement" then
                        for _, generator in ipairs(stmt.Generators or {}) do
                            evalExpr(generator, current)
                        end
                    end
                    local head = cloneEnv(current)
                    while true do
                        local bodyExit = walkList(
                            stmt.Body and stmt.Body.Body, cloneEnv(head), false)
                        local nextHead = mergeEnvs({ current, bodyExit })
                        if envEqual(head, nextHead) then
                            head = nextHead
                            break
                        end
                        head = nextHead
                    end
                    current = head
                elseif t == "ReturnStatement" then
                    for _, value in ipairs(stmt.Arguments or {}) do
                        unionInto(returnDep, evalExpr(value, current))
                    end
                    break
                elseif t == "CallStatement" and stmt.Expression then
                    evalExpr(stmt.Expression, current)
                elseif stmt.Expression then
                    evalExpr(stmt.Expression, current)
                end
            end
            return current
        end

        walkList(summary.node.Body and summary.node.Body.Body, env, true)
        effects.returnSource = returnDep.source == true
        for index in pairs(returnDep.params) do
            effects.returnParams[index] = true
        end
        effects.sinkParams = sinkParams
        stack[summary] = nil
        return effects
    end

    resolveBinderEffects = function(binder, times, fallbackPoint, stack,
            inheritedFunctions)
        local effects = newEffects()
        local values, resolved = resolveValues(
            binder, times, fallbackPoint, {})
        if not resolved then return effects, false end
        for value in pairs(values) do
            if value ~= UNKNOWN_VALUE then
                unionEffects(effects, analyzeSummary(
                    value, times, stack, inheritedFunctions))
            end
        end
        return effects, true
    end

    model.resolve = function(binder, callNode)
        if not binder or not callNode then return nil, false end
        local owner = model.nodeOwners[callNode] or CHUNK_OWNER
        local times = { [owner] = pointFor(callNode) }
        -- A top-level invocation supplies the runtime clock inherited by every
        -- nested wrapper. Calls encountered only while statically walking a
        -- function body have no chunk runtime point; their enclosing call-site
        -- composition will provide it later.
        if owner == CHUNK_OWNER then
            times[CHUNK_OWNER] = pointFor(callNode)
        end
        local effects, resolved = resolveBinderEffects(
            binder, times, pointFor(callNode), {})
        return effects, resolved
    end
    return model
end

resolveIntraFileFunctionSummary = function(model, binder, callNode)
    if not (model and model.resolve and binder) then return nil, false end
    return model.resolve(binder, callNode)
end

--- Analyze a single Lua source string.
--- @param source string  Lua source code.
--- @param filePath string  File path for findings + severity classification.
--- @param registry table  Registry instance (sources/sinks/guards/unwraps).
--- @param config table  Project config (strict_paths/ignore_paths).
--- @param opts table|nil  Options: opts.exposeDebug returns a third debug return value;
---                        opts.includeSuppressed keeps suppressed findings in the list.
--- @return table|nil findings  List of Finding records, or nil on parse error.
--- @return string|nil err  Parse error message.
--- @return table|nil debug  Debug table (only when opts.exposeDebug is true).
function M.analyze(source, filePath, registry, config, opts)
    local ast, err = Parser.parse(source, filePath)
    if not ast then return nil, err end

    opts = opts or {}
    -- Aspect-returning getters only taint inside config aspect_paths; swap in
    -- the aspect-stripped registry view everywhere else (see registry.lua).
    if registry.aspectStripped and not Config.isAspectPath(config, filePath) then
        registry = registry:aspectStripped()
    end
    local functionSummaries =
        collectIntraFileFunctionSummaries(ast, registry)
    local findings = {}
    local taintSet = {}
    local fieldTaintSet = {}
    -- Always allocate debugInfo so annotation pass can always record warnings.
    local debugInfo = { taintedAt = {}, warnings = {} }

    local stmts = ast.Body or {}

    -- Terminator trust (see fnErrorShadowed): computed unconditionally —
    -- bodyTerminates grants protection even in files the needAliases
    -- pre-filter skips.
    fnErrorShadowed = chunkShadowsError(ast)

    -- File-scope alias maps (round-8: the TAINT walk consults these too —
    -- guard aliases in analyzeGuard / the probe-order scan, gate aliases in
    -- the if-statement restriction-dominance rules — so they are built BEFORE
    -- it, not only for the precondition scan).  Textual pre-filter: the AST
    -- walk is skipped when the file never names a guarded API, gate, or
    -- guard.  Alias fixpoint: names with CONFLICTING bindings are poisoned
    -- and the collection re-runs with them blocked, so chains resolved
    -- through a poisoned hop dissolve too (each round can only shrink the
    -- maps — terminates in at most one round per alias name).  The permissive
    -- map/ns stay in use for finding EMISSION; only gate/guard protection
    -- consults `poisoned` (see isGateName / isGuardName).
    local runPreScan = false
    for apiName in pairs(registry.preconditionAPIs or {}) do
        if source:find(getMethodNameFromQualified(apiName), 1, true) then
            runPreScan = true
            break
        end
    end
    local needAliases = runPreScan
    if not needAliases then
        for gname in pairs(registry.restrictionGates or {}) do
            if source:find(getMethodNameFromQualified(gname), 1, true) then
                needAliases = true
                break
            end
        end
    end
    if not needAliases then
        for gname in pairs(registry.guards or {}) do
            if source:find(getMethodNameFromQualified(gname), 1, true) then
                needAliases = true
                break
            end
        end
    end
    -- Element-secret functions (round-23) ride the same alias machinery:
    -- real call sites go through value-copy locals (`local Get =
    -- C_UnitAuras and C_UnitAuras.GetUnitAuras`), so a file naming one
    -- must build the maps or the element track resolves nothing.
    if not needAliases then
        for gname in pairs(registry.elementSecretFunctions or {}) do
            if source:find(getMethodNameFromQualified(gname), 1, true) then
                needAliases = true
                break
            end
        end
    end
    local aliases
    if needAliases then
        local blocked = {}
        repeat
            aliases = { map = {}, ns = {}, binds = {}, poisoned = blocked }
            collectPreconditionAliases(ast, registry, aliases, {})
            local changed = false
            for name, canon in pairs(aliases.map) do
                if not blocked[name] and aliases.binds[name] ~= canon then
                    blocked[name] = true
                    changed = true
                end
            end
            for name, canon in pairs(aliases.ns) do
                if not blocked[name] and aliases.binds[name] ~= canon then
                    blocked[name] = true
                    changed = true
                end
            end
        until not changed
    end

    -- Walk the top-level chunk body. preconditionOnly mode (vendored-lib
    -- coverage via config precondition_only_paths) skips the taint pass —
    -- only the raw guarded-call scan below runs.
    --
    -- Persistent-cache fixpoint (round-10b): pass 1 walks normally and
    -- EXPORTS every tainted field write whose chain root outlives the call
    -- (chunk local / upvalue / global — see exportPersistentKey). If any
    -- key was exported, the walk re-runs with those keys seeded into every
    -- FUNCTION body (walkFunctionBody), modeling the cache-hit read path:
    -- read-before-write inside one function and split Fill/Read functions.
    -- Each extra pass only runs when the export set grew.  The lattice is
    -- finite: exports can contain only AST write keys and lexical binding
    -- classes discovered by this deterministic walk, and both sets grow
    -- monotonically.  Run to the actual fixpoint rather than imposing an
    -- arbitrary depth limit -- a six-cache propagation chain needs a
    -- seventh pass to consume the sixth export.
    if not opts.preconditionOnly then
        local handlerHits = collectRegisteredHandlers(ast, registry)
        local seed = {}
        while true do
            for i = #findings, 1, -1 do findings[i] = nil end
            for k in pairs(taintSet) do taintSet[k] = nil end
            for k in pairs(fieldTaintSet) do fieldTaintSet[k] = nil end
            registeredHandlerHits = handlerHits
            fnEventCtx = newAliasFlowContext(nil)
            fnEventCtx.functionSummaries = functionSummaries
            fnFreshTables = nil
            fnLocalNames = nil
            fnOuterVarNodes = nil
            fnKeyProvenance = nil
            -- Per-pass global binding maps. fnWalkInstance restarts too:
            -- the walk order is deterministic, so qualified IDs are STABLE
            -- across passes — seed classes recorded in pass N stay valid
            -- against pass N+1's privacy maps.
            fnBindingFresh = {}
            fnBindingValueEscaped = {}
            fnBindingDirtyKeys = {}
            fnCapturedUpvalues = {}
            fnWalkInstance = 0
            safeRefSet = {}
            fnAliases = aliases
            fnPersistentSeed = next(seed) ~= nil and seed or nil
            fnPersistentExports = {}
            walkStatements(stmts, taintSet, fieldTaintSet, findings, registry, filePath, debugInfo)
            local grew = false
            for k, classes in pairs(fnPersistentExports) do
                local cur = seed[k]
                local function addOne(c)
                    if not (cur and provMatches(cur, c)) then
                        cur = addProvClass(cur, c)
                        grew = true
                    end
                end
                if type(classes) == "table" then
                    for c in pairs(classes) do addOne(c) end
                else
                    addOne(classes)
                end
                seed[k] = cur
            end
            if not grew then break end
        end
        fnAliases = nil
        safeRefSet = nil
        registeredHandlerHits = nil
        fnEventCtx = nil
        fnFreshTables = nil
        fnLocalNames = nil
        fnOuterVarNodes = nil
        fnKeyProvenance = nil
        fnBindingFresh = nil
        fnBindingValueEscaped = nil
        fnBindingDirtyKeys = nil
        fnCapturedUpvalues = nil
        fnPersistentSeed = nil
        fnPersistentExports = nil
    end

    -- Independent pass: raw calls to precondition-guarded APIs (review tier).
    if runPreScan then
        preconditionScan(ast, registry, filePath, findings, false, {}, aliases)
    end
    fnErrorShadowed = nil

    -- Promote advisory → strict for files in strict_paths
    if Config.isStrictPath(config, filePath) then
        for _, f in ipairs(findings) do
            if f.severity == "advisory" then
                f.severity = "strict"
            end
        end
    end

    if Config.isStrictUnwrapPath(config, filePath) then
        for _, f in ipairs(findings) do
            if f.severity == "review" and f.sink == "<unwrap>" then
                f.severity = "strict"
            end
        end
    end

    -- Promote precondition findings → strict for files in
    -- strict_precondition_paths (audited vendored libs like LibOpenRaid):
    -- once a lib's raw guarded calls are fixed/annotated, a regression fails
    -- CI instead of hiding at review tier. Annotated sites are suppressed
    -- below and never reach the gate.
    if Config.isStrictPreconditionPath and Config.isStrictPreconditionPath(config, filePath) then
        for _, f in ipairs(findings) do
            if f.sink == "<precondition>" then
                f.severity = "strict"
            end
        end
    end

    -- Annotation pass: scan source for -- @secret-safe comments, mark findings.
    local annotations = Annotations.scan(source)
    Annotations.apply(findings, annotations)

    -- Harness warnings: emptyReason annotations on lines that have findings
    for line, a in pairs(annotations) do
        if a.emptyReason then
            for _, f in ipairs(findings) do
                if f.line == line then
                    debugInfo.warnings[#debugInfo.warnings + 1] = string.format(
                        "%s:%d: %s annotation requires a reason",
                        filePath, line,
                        a.kind == "policy" and "@secret-policy" or "@secret-safe")
                    break
                end
            end
        end
    end

    -- Filter suppressed findings unless opts.includeSuppressed
    local filtered
    if opts.includeSuppressed then
        filtered = findings
    else
        filtered = {}
        for _, f in ipairs(findings) do
            if not f.suppressed then
                filtered[#filtered + 1] = f
            end
        end
    end

    if opts.exposeDebug then
        return filtered, nil, debugInfo
    end
    return filtered
end

return M
