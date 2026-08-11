--[[
  tests/helpers/secret_sentinel.lua

  Secret-value sentinel for tests: mimics WoW 12.1 (PTR 68569) secret-value
  semantics well enough to pin the "probe before touching payload args"
  discipline Wave 2 (UNIT_AURA secret boundary) requires. A sentinel errors
  on every operator a real secret value throws on; issecretvalue (stubbed
  via M.InstallSecretStub) recognizes sentinels made by M.MakeSecretSentinel.

  M.MakeSecretSentinel() -> opaque value. Errors on:
    __index, __newindex, __add, __sub, __mul, __div, __concat, __lt, __le
  __eq errors ONLY when comparing two sentinels (they share one metatable —
  see CAVEAT 1). Everything else about a sentinel behaves like a plain empty
  table: it can be stored, used as a table key, tostring()'d, etc.

  M.InstallSecretStub() -> installs _G.issecretvalue = function(v) ... end,
  recognizing every sentinel ever minted by MakeSecretSentinel in this
  process, PLUS the four __QUI_SECRET_TT/EQ/NEQ/LEN helper globals that
  instrumented loads (M.LoadInstrumented below) route through. Returns the
  PREVIOUS _G.issecretvalue so the caller can restore it. NOTE:
  `_G.issecretvalue = restore` is no longer the whole story — it leaves the
  four helper globals installed (harmless: they late-bind issecretvalue at
  CALL time, so with the stub gone they become transparent pass-throughs).
  M.RestoreSecretStub(prev) does the full restore: issecretvalue = prev AND
  removes the helpers.

  M.LoadInstrumented(path) -> chunk, err. Drop-in for loadfile(path): loads
  the module through tests/helpers/secret_instrument.lua's AST-guided
  splicer so truthiness tests, ==/~= (CROSS-TYPE included), and #
  reproduce the in-game 12.1 secret-value throws offline. CAVEATs 1-2
  below describe only the RAW (un-instrumented) sentinel; instrumented
  loads close exactly those gaps. The helpers late-bind _G.issecretvalue,
  so install order vs load order no longer matters for the HELPERS — but
  the module's own `local issecretvalue = issecretvalue` latch still needs
  stub-before-load, see the load-order note below.

  ── CAVEAT 1 — __eq is not a general equality trap (RAW loads only) ─────
  Lua 5.1's __eq only fires when BOTH operands are tables (or both full
  userdata) AND either they share the identical metatable, or both
  metatables define the exact same __eq function object (verified against
  the real get_compTM rule in lvm.c, not just the manual prose — see the
  self-test below for the empirically-checked cases). Concretely:
    sentinel1 == sentinel2   -- THROWS (both share this file's one metatable)
    sentinel  == sentinel    -- no throw (primitively equal; short-circuits
                                 before any metamethod is even considered)
    sentinel  == true/5/"x"  -- no throw (different primitive type; Lua
                                 never calls __eq across types)
    sentinel  == {}          -- no throw (a plain table has no __eq, so
                                 get_compTM finds nothing to call)
  So the RAW fixture CANNOT catch "compare a possibly-secret unit token
  against a known string" bugs — the actual dangerous real-world case, e.g.
  `if unit == "player" then`. That misuse silently evaluates to false here,
  exactly as an untested read would expect. For modules loaded via
  M.LoadInstrumented this gap is CLOSED: every ==/~= routes through
  __QUI_SECRET_EQ/NEQ, which throw when EITHER side is secret, cross-type
  included — offline now matches the real 12.1 behavior. Raw loadfile()
  loads keep the caveat; do not name a raw-load test "equality misuse
  throws" — in the raw case it doesn't, and overclaiming would hide the
  distinction.

  ── CAVEAT 2 — __len is a no-op on tables in Lua 5.1 (RAW loads only) ───
  Lua 5.1 only consults a __len metamethod on full userdata; for tables it
  ALWAYS uses the raw length operation (this changed in Lua 5.2). `#sentinel`
  therefore returns 0 silently — it does not throw, even though __len is set
  below. tools/_addon_env.lua's SECRET_MT documents the identical limitation
  for its own sentinel ("#secret is 0"). Kept in this metatable anyway for
  self-documentation (and in case a future variant proxies through
  userdata); don't assert it throws on a RAW load. Instrumented loads
  rewrite `#x` to `#__QUI_SECRET_LEN(x)`, so there `#secret` DOES throw.
  The same applies to truthiness: raw `if sentinel then` silently takes the
  true branch (table truthiness fires no metamethod); instrumented loads
  route every truth-tested position through __QUI_SECRET_TT and throw.

  ── CAVEAT 3 — string.format("%s", sentinel) throws, but not because of
  this fixture ───────────────────────────────────────────────────────────
  Lua 5.1's string.format requires %s's argument to already be a string or
  number; it throws "string expected, got table" for ANY table (or
  userdata) handed directly to %s, secret or not, __tostring or no
  __tostring. `tostring(sentinel)` itself is always safe (uses __tostring
  below, or the default "table: 0x..." if it didn't exist — never throws).
  The codebase's existing safe pattern is always `string.format("%s",
  tostring(x))`, never a raw value handed to %s; that pattern stays safe
  with sentinels too.

  ── Interop note ─────────────────────────────────────────────────────────
  tools/_addon_env.lua (the dofile("tools/_addon_env.lua") full-harness
  convention used by many tests/unit/*_test.lua files) ALSO installs a
  permanent _G.issecretvalue, against its OWN M.MakeSecret() registry.
  Don't mix the two fixtures in one test process: whichever install ran
  last wins for _G.issecretvalue, and each only recognizes sentinels it
  minted itself.

  ── Load-order note (read before writing Task 2+ tests) ─────────────────
  Several core modules capture the global into a file-local at load time,
  e.g. `local issecretvalue = issecretvalue` (core/aura_events.lua:28) or
  `local issecretvalue = _G.issecretvalue` (core/utils.lua:27). Call
  M.InstallSecretStub() BEFORE loadfile/dofile-ing
  the module under test — installing it after load has NO EFFECT on that
  module, because it already latched the old (nil, in a bare test process)
  value into its own local upvalue.

  Usage (from a test, cwd = repo root):
    local SecretSentinel = dofile("tests/helpers/secret_sentinel.lua")
    local restore = SecretSentinel.InstallSecretStub()  -- BEFORE loading the module
    local ns = {}
    assert(loadfile("core/aura_events.lua"))("QUI", ns)
    local secret = SecretSentinel.MakeSecretSentinel()
    -- ... exercise ns against `secret` ...
    _G.issecretvalue = restore

  Self-test: lua5.1 tests/helpers/secret_sentinel.lua --test
]]

local M = {}

-- Every sentinel ever minted in this process, weak-keyed so they can be GC'd.
local SECRETS = setmetatable({}, { __mode = "k" })

local function throw()
    error("attempt to use a secret value", 2)
end

-- Deliberately ONE generic message for every trapped operator: these tests
-- only need to know an operation threw, not which one (unlike
-- tools/_addon_env.lua's SECRET_MT, which differentiates index vs write).
local secretMT = {
    __index    = throw,
    __newindex = throw,
    __eq       = throw, -- CAVEAT 1: only fires sentinel-vs-sentinel
    __lt       = throw,
    __le       = throw,
    __add      = throw,
    __sub      = throw,
    __mul      = throw,
    __div      = throw,
    __concat   = throw,
    __len      = throw, -- CAVEAT 2: inert on tables in Lua 5.1
    __tostring = function() return "<secret>" end, -- keeps tostring()/debug output legible; string.format("%s", sentinel) is still unsafe, see CAVEAT 3
    __metatable = false, -- getmetatable() returns false; setmetatable() on a sentinel errors
}

-- Each call returns a distinct opaque value that InstallSecretStub's stub
-- reports as secret.
function M.MakeSecretSentinel()
    local s = setmetatable({}, secretMT)
    SECRETS[s] = true
    return s
end

-- Shared guts of the __QUI_SECRET_* helper globals used by instrumented
-- loads. Late-binds _G.issecretvalue at CALL time (rawget: strict-_G safe)
-- so the helpers compose with this fixture OR tools/_addon_env.lua's own
-- issecretvalue, whichever is currently installed. Transparent for every
-- non-secret value, including nil/false. error level 3 = the instrumented
-- caller's line (1 secretcheck, 2 helper, 3 instrumented code).
local function secretcheck(v, what)
    local isv = rawget(_G, "issecretvalue")
    if isv and isv(v) then
        error("attempt to " .. what .. " a secret value", 3)
    end
    return v
end

-- Installs _G.issecretvalue recognizing every sentinel minted by
-- MakeSecretSentinel, plus the four __QUI_SECRET_* helper globals that
-- instrumented loads call. Returns the previous _G.issecretvalue for
-- restore (`_G.issecretvalue = restore` keeps working, but leaves the
-- helpers installed — use M.RestoreSecretStub(restore) for the full
-- unwind). See the load-order note above: call this BEFORE loading the
-- module under test, not after.
function M.InstallSecretStub()
    local prev = _G.issecretvalue
    _G.issecretvalue = function(v)
        return SECRETS[v] == true
    end
    _G.__QUI_SECRET_TT  = function(v) return secretcheck(v, "perform boolean test on") end
    _G.__QUI_SECRET_LEN = function(v) return secretcheck(v, "get length of") end
    _G.__QUI_SECRET_EQ  = function(a, b)
        secretcheck(a, "compare"); secretcheck(b, "compare")
        return a == b
    end
    _G.__QUI_SECRET_NEQ = function(a, b)
        secretcheck(a, "compare"); secretcheck(b, "compare")
        return a ~= b
    end
    return prev
end

-- Full restore: puts back the previous issecretvalue AND removes the four
-- helper globals InstallSecretStub added.
function M.RestoreSecretStub(prev)
    _G.issecretvalue = prev
    _G.__QUI_SECRET_TT  = nil
    _G.__QUI_SECRET_LEN = nil
    _G.__QUI_SECRET_EQ  = nil
    _G.__QUI_SECRET_NEQ = nil
end

-- Load a module with throw-semantics instrumentation (truthiness, ==/~=,
-- #). Drop-in for loadfile(): returns chunk, err. Requires
-- InstallSecretStub() to have run for the throws to fire (the helpers
-- late-bind issecretvalue, so install order vs load order no longer
-- matters for the HELPERS — the module's own
-- `local issecretvalue = issecretvalue` latch still needs
-- stub-before-load, see the load-order note above).
local Instrument -- lazy: only instrumented tests pay the parser load
function M.LoadInstrumented(path)
    Instrument = Instrument or dofile("tests/helpers/secret_instrument.lua")
    return Instrument.loadFile(path)
end

----------------------------------------------------------------------------
-- Self-test (also pins the CAVEATs above so nobody "fixes" a doc comment
-- into an overclaim later without a test noticing).
----------------------------------------------------------------------------
local function throws(fn)
    return not pcall(fn)
end

local function SelfTest()
    local outerRestore = M.InstallSecretStub()

    local s  = M.MakeSecretSentinel()
    local s2 = M.MakeSecretSentinel()
    assert(s ~= nil and s2 ~= nil, "sentinels must be non-nil")

    -- predicate
    assert(issecretvalue(s) == true,  "stub recognizes sentinel")
    assert(issecretvalue(s2) == true, "stub recognizes every sentinel it minted")
    assert(issecretvalue({}) == false,   "plain table not secret")
    assert(issecretvalue(42) == false,   "number not secret")
    assert(issecretvalue("x") == false,  "string not secret")
    assert(issecretvalue(true) == false, "boolean not secret")
    assert(issecretvalue(nil) == false,  "nil not secret")

    -- index / newindex throw
    assert(throws(function() return s.isFullUpdate end), "index throws")
    assert(throws(function() s.isFullUpdate = 1 end),    "newindex throws")

    -- arithmetic throws, both operand orders
    assert(throws(function() return s + 1 end), "s + n throws")
    assert(throws(function() return 1 + s end), "n + s throws")
    assert(throws(function() return s - 1 end), "subtraction throws")
    assert(throws(function() return s * 1 end), "multiplication throws")
    assert(throws(function() return s / 1 end), "division throws")

    -- concat throws, both operand orders
    assert(throws(function() return "x" .. s end), "string .. sentinel throws")
    assert(throws(function() return s .. "x" end), "sentinel .. string throws")

    -- relational throws — unlike __eq, __lt/__le have no same-type gate:
    -- either operand carrying the metamethod is enough (verified below).
    assert(throws(function() return s < 1 end),  "s < n throws")
    assert(throws(function() return 1 < s end),  "n < s throws")
    assert(throws(function() return s <= 1 end), "s <= n throws")
    assert(throws(function() return s < s2 end), "s < s2 (both sentinels) throws")

    -- CAVEAT 1, empirically pinned:
    assert(throws(function() return s == s2 end), "two DISTINCT sentinels compared via == throw (shared metatable fast path)")
    assert(s == s, "a sentinel compared to itself is primitively equal — no metamethod call, no throw")
    assert((s == true) == false, "sentinel == boolean is a cross-type compare — never reaches __eq, no throw, just false")
    assert((s == 5) == false,    "sentinel == number is a cross-type compare — never reaches __eq, no throw, just false")
    assert((s == {}) == false,   "sentinel == plain-table — plain table has no __eq, get_compTM finds nothing, no throw, just false")
    assert(s ~= 5, "cross-type ~= likewise never throws")

    -- CAVEAT 2, empirically pinned: __len is inert on tables in Lua 5.1.
    assert(not throws(function() return #s end), "length must NOT throw here (Lua 5.1 __len is userdata-only) — do not overclaim this in future edits")
    assert(#s == 0, "length silently reads the sentinel's raw (empty) table size")

    -- Storing/keying by a sentinel is plain table mechanics, not an
    -- operation ON the sentinel — must never throw. (The original wave-2
    -- plan draft asserted the opposite for `t[s] = 1`; that assertion was
    -- wrong and would have failed here — corrected.)
    local t = {}
    assert(not throws(function() t[s] = "tagged" end), "using a sentinel as a table key/value must not throw")
    assert(t[s] == "tagged", "the stored value must be retrievable via the sentinel key")

    -- tostring is always safe (that's how __tostring above is exercised;
    -- see CAVEAT 3 for why string.format("%s", s) directly is NOT safe).
    assert(tostring(s) == "<secret>", "tostring(sentinel) must be safe and legible")
    assert(throws(function() return string.format("%s", s) end), "string.format(\"%s\", sentinel) DOES throw in Lua 5.1 (table handed directly to %s) — always wrap in tostring() first")
    assert(not throws(function() return string.format("%s", tostring(s)) end), "string.format(\"%s\", tostring(sentinel)) is the codebase's actual safe pattern")

    -- restore + re-install composability
    _G.issecretvalue = outerRestore
    assert(_G.issecretvalue == nil, "restoring a bare test process's stub returns issecretvalue to nil")

    local restoreA = M.InstallSecretStub()
    local stubA = _G.issecretvalue
    assert(restoreA == nil, "first install in this process still had nothing to restore")
    local restoreB = M.InstallSecretStub()
    assert(restoreB == stubA, "InstallSecretStub must return the PREVIOUS stub so callers can chain/restore")
    _G.issecretvalue = restoreB
    assert(_G.issecretvalue == stubA, "restore chain unwinds to the prior stub")
    _G.issecretvalue = nil -- leave the process clean

    -- Instrumented-load block: LoadInstrumented/secret_instrument closes the
    -- raw CAVEATs (truthiness + cross-type ==) for modules loaded through it.
    -- The raw assertions above still pin the un-instrumented behavior.
    local restoreI = M.InstallSecretStub()
    assert(type(rawget(_G, "__QUI_SECRET_TT")) == "function"
        and type(rawget(_G, "__QUI_SECRET_EQ")) == "function"
        and type(rawget(_G, "__QUI_SECRET_NEQ")) == "function"
        and type(rawget(_G, "__QUI_SECRET_LEN")) == "function",
        "InstallSecretStub must install the four instrumentation helpers")
    local Instrument = dofile("tests/helpers/secret_instrument.lua")
    local si = M.MakeSecretSentinel()
    local chunk = assert(Instrument.loadString("local s = ...\nif s then end", "=inst"))
    assert(throws(function() chunk(si) end),
        "instrumented `if secret` must throw (raw truthiness caveat closed)")
    local chunk2 = assert(Instrument.loadString('local s = ...\nreturn s == "player"', "=inst2"))
    assert(throws(function() chunk2(si) end),
        "instrumented cross-type == must throw (CAVEAT 1 closed)")
    local chunk3 = assert(Instrument.loadString(
        'local s = ...\nif issecretvalue(s) then return "probed" end\nreturn "missed"', "=inst3"))
    local okProbe, probeResult = pcall(chunk3, si)
    assert(okProbe and probeResult == "probed",
        "probe-first discipline must pass under instrumentation")
    M.RestoreSecretStub(restoreI)
    assert(rawget(_G, "__QUI_SECRET_TT") == nil
        and rawget(_G, "__QUI_SECRET_EQ") == nil
        and rawget(_G, "__QUI_SECRET_NEQ") == nil
        and rawget(_G, "__QUI_SECRET_LEN") == nil,
        "RestoreSecretStub must remove all four helpers")
    assert(_G.issecretvalue == nil, "RestoreSecretStub must restore issecretvalue")

    print("secret_sentinel self-test: OK")
end

M.SelfTest = SelfTest

-- arg[0] scoping: dofile-ing this helper from ANOTHER script running with
-- --test (e.g. secret_instrument.lua --test) must not auto-fire this
-- self-test.
if arg and arg[1] == "--test"
    and tostring(arg[0] or ""):find("secret_sentinel", 1, true) then
    SelfTest()
end

return M
