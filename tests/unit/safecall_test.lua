-- tests/unit/safecall_test.lua
-- Behavioral tests + source-text contract pins for core/safecall.lua.
-- Run: lua5.1 tests/unit/safecall_test.lua
local fails = 0
local function check(name, ok)
    if ok then print("  ok  " .. name)
    else fails = fails + 1; print("FAIL  " .. name) end
end

local function pack(...)
    return select("#", ...), { ... }
end

---------------------------------------------------------------------------
-- Stubs (installed BEFORE load: safecall captures issecretvalue at load;
-- geterrorhandler is resolved lazily at failure time).
---------------------------------------------------------------------------
-- Sentinel whose tostring THROWS: proves the secret probe runs before any
-- tostring/find/format touches the err.
local secretSentinel = setmetatable({}, {
    __tostring = function() error("PROBE-ORDER VIOLATION: secret err was tostring'd") end,
})
issecretvalue = function(v) return v == secretSentinel end

local handlerCalls = {}
geterrorhandler = function()
    return function(err) handlerCalls[#handlerCalls + 1] = err end
end

local chunk = assert(loadfile("core/safecall.lua"))
local ns = {}
chunk("QUI", ns)
local st = ns.SafeCallStats()

---------------------------------------------------------------------------
-- 1. success passthrough
---------------------------------------------------------------------------
local function multi(a, b) return a + b, nil, "three" end
local n, r = pack(ns.SafeCall("report", multi, 2, 3))
check("success forwards all returns exactly (pcall shape)",
    n == 4 and r[1] == true and r[2] == 5 and r[3] == nil and r[4] == "three")
check("success never touches the error handler", #handlerCalls == 0)

---------------------------------------------------------------------------
-- 2. expected class: silent, counted
---------------------------------------------------------------------------
local ok = ns.SafeCall("defer-ooc", function() error("attempt to compare a secret value blah") end)
check("expected-class err returns false, handler silent, expected=1",
    ok == false and #handlerCalls == 0 and st["defer-ooc"].expected == 1)

---------------------------------------------------------------------------
-- 3. unexpected: dedup reports once, counts every time
---------------------------------------------------------------------------
local function boom() error("identical boom") end
ns.SafeCall("bulkhead", boom)
ns.SafeCall("bulkhead", boom)
ns.SafeCall("bulkhead", boom)
check("identical unexpected err reported ONCE", #handlerCalls == 1)
check("unexpected counted on every failure", st.bulkhead.unexpected == 3)

---------------------------------------------------------------------------
-- 4. distinct errs each reported once
---------------------------------------------------------------------------
local before = #handlerCalls
ns.SafeCall("sink-forward", function() error("distinct err A") end)
ns.SafeCall("sink-forward", function() error("distinct err B") end)
check("distinct errs each reported", #handlerCalls == before + 2)

---------------------------------------------------------------------------
-- 5. secret err: probe first, handler every time, no dedup
---------------------------------------------------------------------------
before = #handlerCalls
local function secretBoom() error(secretSentinel) end
local s1 = ns.SafeCall("park-fail-closed", secretBoom)
local s2 = ns.SafeCall("park-fail-closed", secretBoom)
local s3 = ns.SafeCall("park-fail-closed", secretBoom)
check("secret err returns false each time", s1 == false and s2 == false and s3 == false)
check("secret err handler called every time (dedup skipped)", #handlerCalls == before + 3)
check("secret err forwarded raw to handler", handlerCalls[#handlerCalls] == secretSentinel)
check("secretErr counted per failure", st["park-fail-closed"].secretErr == 3)

---------------------------------------------------------------------------
-- 6. unknown policy: no crash, badpolicy bump, report-only routing
---------------------------------------------------------------------------
before = #handlerCalls
ok = ns.SafeCall("park-fail-clsoed", function() error("combat lockdown under typo") end)
check("unknown policy never crashes, returns false", ok == false)
check("badpolicy counted", st.badpolicy == 1)
check("unknown policy routed report-only (expected class still LOUD)",
    #handlerCalls == before + 1 and st.report.unexpected == 1)

---------------------------------------------------------------------------
-- 7. SafeCallMethod: self passed; index inside pcall
---------------------------------------------------------------------------
local obj = { tag = "T", get = function(self, x) return self.tag .. x end }
n, r = pack(ns.SafeCallMethod("best-effort-style", obj, "get", "!"))
check("SafeCallMethod calls method with self", n == 2 and r[1] == true and r[2] == "T!")
before = #handlerCalls
local forb = setmetatable({}, { __index = function() error("forbidden object") end })
ok = ns.SafeCallMethod("best-effort-style", forb, "Anything")
check("throwing index caught inside pcall, classed expected",
    ok == false and st["best-effort-style"].expected == 1 and #handlerCalls == before)
ok = ns.SafeCallMethod("best-effort-style", nil, "x")
check("nil obj caught inside pcall", ok == false)

---------------------------------------------------------------------------
-- 7b. SafeCallMethodIfPresent: existence probe INSIDE pcall
---------------------------------------------------------------------------
n, r = pack(ns.SafeCallMethodIfPresent("best-effort-style", obj, "get", "?"))
check("IfPresent calls an existing method with self", n == 2 and r[1] == true and r[2] == "T?")
before = #handlerCalls
n, r = pack(ns.SafeCallMethodIfPresent("best-effort-style", obj, "absent"))
check("IfPresent absent method = SKIP: returns exactly nil, never true",
    n == 1 and r[1] == nil and #handlerCalls == before)
n, r = pack(ns.SafeCallMethodIfPresent("best-effort-style", nil, "x"))
check("IfPresent nil obj = SKIP (nil), silent",
    n == 1 and r[1] == nil and #handlerCalls == before)
ok = ns.SafeCallMethodIfPresent("best-effort-style", forb, "Anything")
check("IfPresent throwing __index caught inside pcall, returns false (classed expected)",
    ok == false and #handlerCalls == before)
n, r = pack(ns.SafeCallMethodIfPresent("best-effort-style", secretSentinel, "x"))
check("IfPresent secret obj probed first, SKIP (nil) — no == nil throw path",
    n == 1 and r[1] == nil and #handlerCalls == before)
check("IfPresent three states distinct: called=true, skipped=nil, error=false",
    select(1, ns.SafeCallMethodIfPresent("best-effort-style", obj, "get", "!")) == true
    and ns.SafeCallMethodIfPresent("best-effort-style", obj, "absent") == nil
    and ns.SafeCallMethodIfPresent("best-effort-style", forb, "Anything") == false)

---------------------------------------------------------------------------
-- 8. observer
---------------------------------------------------------------------------
local obs = {}
ns.SafeCallSetObserver(function(p, e, w) obs[#obs + 1] = { p = p, e = e, w = w } end)
ns.SafeCall("compat", function() error("secret value seen by observer") end)
ns.SafeCall("compat", function() error("plain err seen by observer") end)
ns.SafeCall("compat", secretBoom)
check("observer got expected + unexpected plain errs, with flags",
    #obs == 2 and obs[1].w == true and obs[2].w == false
    and obs[1].p == "compat" and type(obs[1].e) == "string" and type(obs[2].e) == "string")
check("observer NOT called for secret err", #obs == 2)
ns.SafeCallSetObserver(function() error("broken observer") end)
ok = ns.SafeCall("compat", function() error("observer must not break handling") end)
check("throwing observer does not propagate", ok == false and st.compat.unexpected == 2)
ns.SafeCallSetObserver(nil)
ns.SafeCall("compat", function() error("after observer cleared") end)
check("nil clears observer", #obs == 2)

---------------------------------------------------------------------------
-- 8b. non-secret error OBJECTS: hostile __tostring must not escape
---------------------------------------------------------------------------
before = #handlerCalls
local hostileErr = setmetatable({}, {
    __tostring = function() error("hostile __tostring") end,
})
local okHostile = pcall(function()
    ok = ns.SafeCall("bulkhead", function() error(hostileErr) end)
end)
check("throwing __tostring on a NON-secret err does not escape the bulkhead",
    okHostile == true and ok == false)
check("unprintable err still reported via synthetic message",
    #handlerCalls == before + 1
    and tostring(handlerCalls[#handlerCalls]):find("unprintable error object", 1, true) ~= nil)

-- tostring SUCCEEDS but returns a secret (the stub's sentinel): must route
-- the secret path — never reach strfind/dedup-index.
before = #handlerCalls
local sb = st.bulkhead.secretErr or 0
ok = ns.SafeCall("bulkhead", function() error(setmetatable({}, {
    __tostring = function() return secretSentinel end,
})) end)
check("__tostring returning a secret routes the secret path (no find/index)",
    ok == false and st.bulkhead.secretErr == sb + 1
    and handlerCalls[#handlerCalls] == secretSentinel)

---------------------------------------------------------------------------
-- 8c. throwing INSTALLED handler must not escape (handler dispatch is part
--     of the failure path — a broken error grabber would otherwise defeat
--     the bulkhead for every error class)
---------------------------------------------------------------------------
local goodHandler = geterrorhandler
geterrorhandler = function()
    return function() error("handler itself is broken") end
end
-- Named raiser: called again after the handler heals, so the err string
-- (error() prepends file:line) is IDENTICAL across both attempts — the
-- retry checks below depend on dedup seeing the same key.
local function transientBoom() error("plain err, broken handler") end
local su = st["sink-forward"].unexpected
local okPlain = pcall(function()
    ok = ns.SafeCall("sink-forward", transientBoom)
end)
check("throwing handler contained for a PLAIN unexpected err",
    okPlain == true and ok == false and st["sink-forward"].unexpected == su + 1)
local ss = st["sink-forward"].secretErr or 0
local okSecret = pcall(function()
    ok = ns.SafeCall("sink-forward", secretBoom)
end)
check("throwing handler contained for a SECRET err (still counted)",
    okSecret == true and ok == false and st["sink-forward"].secretErr == ss + 1)
-- geterrorhandler ITSELF throwing (grabber mid-replacement): still contained.
geterrorhandler = function() error("no handler installed") end
local okNoHandler = pcall(function()
    ok = ns.SafeCall("sink-forward", function() error("err with broken geterrorhandler") end)
end)
check("throwing geterrorhandler contained (report skipped, no escape)",
    okNoHandler == true and ok == false)
geterrorhandler = goodHandler

---------------------------------------------------------------------------
-- 8d. transient handler failure must NOT permanently silence the err:
--     non-delivery rolls the dedup mark back, so with the handler healed
--     the SAME err reports on its next occurrence — then dedup re-arms.
---------------------------------------------------------------------------
before = #handlerCalls
ok = ns.SafeCall("sink-forward", transientBoom)
check("undelivered err retries once the handler heals (no permanent silence)",
    ok == false and #handlerCalls == before + 1
    and tostring(handlerCalls[#handlerCalls]):find("plain err, broken handler", 1, true) ~= nil)
ok = ns.SafeCall("sink-forward", transientBoom)
check("delivered report re-arms dedup (next occurrence silent)",
    ok == false and #handlerCalls == before + 1)

---------------------------------------------------------------------------
-- 8e. REENTRANT handler dispatch: a handler whose own work fails back
--     through SafeCall with a UNIQUE err each time defeats the string-keyed
--     dedup (it only stops IDENTICAL re-raises) and would recurse handler-
--     inside-handler until C-stack exhaustion. The active-dispatch sentinel
--     caps live dispatch at ONE; a nested report declines as non-delivery
--     so its dedup mark rolls back and the err retries independently.
---------------------------------------------------------------------------
local nestedSeq, handlerEntries, active, maxActive = 0, 0, 0, 0
geterrorhandler = function()
    return function()
        handlerEntries = handlerEntries + 1
        active = active + 1
        if active > maxActive then maxActive = active end
        nestedSeq = nestedSeq + 1
        ns.SafeCall("bulkhead", function() error("reentrant unique err " .. nestedSeq) end)
        active = active - 1
    end
end
ok = ns.SafeCall("sink-forward", function() error("reentrant top-level err") end)
check("reentrant handler with UNIQUE nested errs: one dispatch, no recursion",
    ok == false and handlerEntries == 1 and maxActive == 1)

-- Handler RESOLUTION is a reentry surface too: geterrorhandler is grabber-
-- replaceable, so a grabber that fails back through SafeCall with UNIQUE
-- errs while RESOLVING recurses exactly like a throwing handler body would
-- — the latch must be set before resolution, not after.
local resolveEntries = 0
geterrorhandler = function()
    resolveEntries = resolveEntries + 1
    nestedSeq = nestedSeq + 1
    ns.SafeCall("bulkhead", function() error("resolution-path unique err " .. nestedSeq) end)
    return function(err) handlerCalls[#handlerCalls + 1] = err end
end
before = #handlerCalls
ok = ns.SafeCall("sink-forward", function() error("resolution reentrant top err") end)
check("reentrant handler RESOLUTION with unique nested errs: one resolution, no recursion",
    ok == false and resolveEntries == 1)
check("resolution reentry still delivers the top-level err afterwards",
    #handlerCalls == before + 1
    and tostring(handlerCalls[#handlerCalls]):find("resolution reentrant top err", 1, true) ~= nil)

-- Declined nested report must roll back its dedup mark: once dispatch is
-- over (handler healed), the same nested err delivers on its next occurrence.
local function nestedBoom() error("nested err during dispatch", 0) end
geterrorhandler = function()
    return function() ns.SafeCall("bulkhead", nestedBoom) end
end
ns.SafeCall("sink-forward", function() error("reentrant top-level err 2") end)
geterrorhandler = goodHandler
before = #handlerCalls
ns.SafeCall("bulkhead", nestedBoom)
check("nested err declined mid-dispatch retries after dispatch ends (mark rolled back)",
    #handlerCalls == before + 1
    and handlerCalls[#handlerCalls] == "nested err during dispatch")

---------------------------------------------------------------------------
-- 8f. REENTRANT observer: the observer runs BEFORE dedup and BEFORE the
--     handler latch, so an observer whose own work fails back through
--     SafeCall with a UNIQUE err each time recurses observer-inside-
--     observer toward C-stack exhaustion — dedup never sees an identical
--     key. The observer latch caps live observer dispatch at ONE; nested
--     failures still count, only their observer notification is dropped,
--     and the latch releases for the next independent failure.
---------------------------------------------------------------------------
local obsSeq, obsEntries, obsActive, obsMaxActive = 0, 0, 0, 0
ns.SafeCallSetObserver(function()
    obsEntries = obsEntries + 1
    obsActive = obsActive + 1
    if obsActive > obsMaxActive then obsMaxActive = obsActive end
    -- Depth cap keeps an UNFIXED run fast; the latch check below still
    -- fails on any nesting at all.
    if obsActive < 8 then
        obsSeq = obsSeq + 1
        ns.SafeCall("bulkhead", function() error("observer reentrant unique err " .. obsSeq) end)
    end
    obsActive = obsActive - 1
end)
ok = ns.SafeCall("sink-forward", function() error("observer reentrant top err") end)
check("reentrant observer with UNIQUE nested errs: one dispatch, no recursion",
    ok == false and obsEntries == 1 and obsMaxActive == 1)
obsEntries = 0
ns.SafeCall("sink-forward", function() error("observer post-latch err") end)
check("observer latch releases after dispatch (next failure observed)",
    obsEntries == 1)
ns.SafeCallSetObserver(nil)

---------------------------------------------------------------------------
-- 9. failure returns exactly false
---------------------------------------------------------------------------
n, r = pack(ns.SafeCall("defer-lift", function() error("only false out") end))
check("failure returns exactly one value: false", n == 1 and r[1] == false)

---------------------------------------------------------------------------
-- 10. every expected-class literal matches
---------------------------------------------------------------------------
local patterns = {
    "secret value",
    "Cannot use SecureHandlers API on forbidden frames",
    "Cannot use SecureHandlers API during combat",
    "forbidden object",
    "attempted to store a secret",
    "combat lockdown",
    "ADDON_ACTION_BLOCKED",
}
before = #handlerCalls
for i = 1, #patterns do
    ns.SafeCall("chain-next", function() error("x " .. patterns[i] .. " y") end)
end
check("all 7 expected-class literals match silently",
    st["chain-next"].expected == 7 and #handlerCalls == before)

---------------------------------------------------------------------------
-- Source-text contract pins
---------------------------------------------------------------------------
local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local d = f:read("*a"); f:close()
    return (d:gsub("\r\n", "\n"))
end
local src = readAll("core/safecall.lua")

local probePos = src:find("issecretvalue(err)", 1, true)
local tostringPos = src:find("pcall(tostring, err)", 1, true)
check("pin: secret probe BEFORE the (protected) tostring of err",
    probePos ~= nil and tostringPos ~= nil and probePos < tostringPos)
check("pin: tostring of err is pcall-protected (hostile __tostring must not escape)",
    src:find("%serr = tostring%(err%)") == nil)
check("pin: probe-order constraint cites Blizzard_ScriptErrorsFrame.lua:95-105",
    src:find("Blizzard_ScriptErrorsFrame.lua:95-105", 1, true) ~= nil)
check("pin: handler invocation is pcall-protected (no raw currentHandler()(...) call)",
    src:find("currentHandler()(", 1, true) == nil
    and src:find("pcall(handler, err)", 1, true) ~= nil)
check("pin: handler RESOLUTION is protected too (secret/throwing geterrorhandler)",
    src:find("pcall(currentHandler)", 1, true) ~= nil)
check("pin: non-delivery rolls back the dedup mark (no permanent silence)",
    src:find("if not reportToHandler(err) then", 1, true) ~= nil
    and src:find("seen[err] = nil", 1, true) ~= nil)
check("pin: reentrant handler dispatch declines (active-dispatch sentinel)",
    src:find("if dispatching then return false end", 1, true) ~= nil)
local latchPos = src:find("dispatching = true", 1, true)
local resolvePos = src:find("pcall(currentHandler)", 1, true)
check("pin: latch set BEFORE handler resolution (grabber re-enters via geterrorhandler)",
    latchPos ~= nil and resolvePos ~= nil and latchPos < resolvePos)
check("pin: reentrant observer dispatch declines (observer latch)",
    src:find("if not observer or observing then return end", 1, true) ~= nil)
check("pin: observer notifications route through the latched dispatcher only",
    src:find("notifyObserver(policy, err, true)", 1, true) ~= nil
    and src:find("notifyObserver(policy, err, false)", 1, true) ~= nil
    and src:find("if observer then pcall(observer", 1, true) == nil)

local policies = {
    "park-fail-closed", "defer-ooc", "defer-lift", "chain-next", "sink-forward",
    "best-effort-style", "bulkhead", "compat", "report",
}
local allPolicies = true
for i = 1, #policies do
    if not src:find('"' .. policies[i] .. '"', 1, true) then allPolicies = false end
end
check("pin: policy registry contains all 9 names", allPolicies)

check("pin: fixed method trampoline allocated once at load",
    src:find("local function invoke", 1, true) ~= nil)

local bodyStart = src:find("function ns.SafeCall(policy, fn", 1, true)
local bodyEnd = src:find("\nend", bodyStart, true)
local body = bodyStart and bodyEnd and src:sub(bodyStart, bodyEnd)
check("pin: SafeCall success path allocates no closure",
    body ~= nil and body:find("function(", 1, true) == nil)

if fails > 0 then error(fails .. " failure(s) in safecall_test") end
print("OK: safecall_test (all checks passed)")
