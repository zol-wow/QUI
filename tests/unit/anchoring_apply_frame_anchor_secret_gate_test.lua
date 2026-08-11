-- tests/unit/anchoring_apply_frame_anchor_secret_gate_test.lua
-- Run: lua tests/unit/anchoring_apply_frame_anchor_secret_gate_test.lua
--
-- BEHAVIORAL harness for the central anchoring implementation: loads the
-- REAL modules/layout/anchoring.lua chunk (setfenv'd into a stub WoW
-- environment) together with the REAL core/utils.lua helpers, then drives
-- _G.QUI_ApplyFrameAnchor end to end. This is the companion to the static
-- source tests — it proves runtime behavior, not source text:
--
--   (a) COMBAT MUTATION GATE POLARITY (fail-closed): in combat the apply
--       path probes the resolved frame through Helpers.FrameMutationRestricted.
--       A provably-unrestricted frame (both getters false) IS repositioned
--       mid-combat; a true, SECRET, or THROWING answer defers — no geometry
--       call reaches the frame — and PLAYER_REGEN_ENABLED reconciles the
--       deferred apply.
--   (b) hideWithParent VISIBILITY READS ARE SECRET-SAFE: the parent's
--       IsShown/GetAlpha answers drive Hide/Show of the child. A readable
--       answer behaves as before (hidden parent hides child, alpha ~ 0
--       counts as hidden, reappearing parent restores). A SECRET or
--       THROWING answer from either getter defers the hide/show DECISION:
--       the child is neither hidden nor shown on a guess and no error
--       escapes. Out of combat the child is still POSITIONED (so an
--       unreadable parent can never strand it unanchored) and ONE
--       fresh-stack C_Timer.After(0) retry per unreadable episode
--       re-evaluates — never an every-frame poll loop. In combat the whole
--       apply defers and latches the regen reconcile.
--   (c) Helpers.FrameVisibleSecure tri-state contract (true/false/nil).
--
-- The SECRET sentinel here is an ordinary Lua table (truth-testing it
-- cannot throw the way a real 12.1 secret does), so the assertions are
-- BEHAVIORAL: the unfixed code paths proceed to Hide/Show/SetPoint when
-- handed a secret, the fixed paths must record NO mutation at all.

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

---------------------------------------------------------------------------
-- Shared helpers (real core/utils.lua), secret sentinel installed first.
---------------------------------------------------------------------------
local SECRET = setmetatable({}, { __tostring = function() return "SECRET" end })
local function fakeIsSecretValue(v) return v == SECRET end
_G.issecretvalue = fakeIsSecretValue
_G.LibStub = function() return nil end

local ns = {
    -- modules/layout/anchoring.lua now routes its pcall guards through
    -- ns.SafeCall (Task 45d); mirror the ns-mock stub precedent used
    -- across the suite.
    SafeCall = function(_policy, fn, ...) return pcall(fn, ...) end,
    SafeCallMethod = function(_policy, obj, name, ...) return pcall(function(...) return obj[name](obj, ...) end, ...) end,
    SafeCallMethodIfPresent = function(_policy, obj, name, ...) if obj == nil then return nil end local okP, m = pcall(function() return obj[name] end) if not okP then return false end if m == nil then return nil end return pcall(m, obj, ...) end,
}
assert(loadfile("core/utils.lua"))("QUI", ns)
assert(ns.Helpers and ns.Helpers.FrameMutationRestricted,
    "core/utils.lua must export Helpers.FrameMutationRestricted")
assert(ns.Helpers.FrameVisibleSecure,
    "core/utils.lua must export the secret-safe Helpers.FrameVisibleSecure")

local failures = 0
local function check(name, ok, detail)
    if ok then
        print(("  ok  %s"):format(name))
    else
        failures = failures + 1
        print(("FAIL  %s  %s"):format(name, detail or ""))
    end
end

---------------------------------------------------------------------------
-- Part (c) first: FrameVisibleSecure tri-state contract on the real helper.
---------------------------------------------------------------------------
local FVS = ns.Helpers.FrameVisibleSecure
local function visFrame(shown, alpha)
    return {
        IsShown = function() return shown end,
        GetAlpha = function() return alpha end,
    }
end
check("FVS: nil frame -> false (provably hidden)", FVS(nil) == false)
check("FVS: missing IsShown -> false", FVS({}) == false)
check("FVS: shown alpha 1 -> true", FVS(visFrame(true, 1)) == true)
check("FVS: not shown -> false", FVS(visFrame(false, 1)) == false)
check("FVS: shown alpha 0 -> false", FVS(visFrame(true, 0)) == false)
check("FVS: shown, no GetAlpha -> true",
    FVS({ IsShown = function() return true end }) == true)
check("FVS: secret IsShown -> nil (defer)", FVS(visFrame(SECRET, 1)) == nil)
check("FVS: secret GetAlpha -> nil (defer)", FVS(visFrame(true, SECRET)) == nil)
check("FVS: throwing IsShown -> nil (defer)",
    FVS({ IsShown = function() error("secure-context") end }) == nil)
check("FVS: throwing GetAlpha -> nil (defer)",
    FVS({
        IsShown = function() return true end,
        GetAlpha = function() error("secure-context") end,
    }) == nil)
check("FVS: custom threshold hides below it",
    FVS(visFrame(true, 0.3), 0.5) == false)

-- Member LOOKUP throws (forbidden frame / 68675 DenyTaintedAccess child —
-- round-18b guard-position class): the getter index itself detonates, not
-- the call. Unprovable -> nil, and the throw must never escape the helper.
local function lookupThrowFrame(throwMembers, base)
    return setmetatable({}, {
        __index = function(_, k)
            if throwMembers[k] then
                error("Attempted to read forbidden member " .. tostring(k))
            end
            return base and base[k] or nil
        end,
    })
end
local okL, resL = pcall(FVS, lookupThrowFrame({ IsShown = true }))
check("FVS: throwing IsShown LOOKUP -> nil (defer, no escape)",
    okL and resL == nil, tostring(resL))
okL, resL = pcall(FVS, lookupThrowFrame({ GetAlpha = true },
    { IsShown = function() return true end }))
check("FVS: throwing GetAlpha LOOKUP -> nil (defer, no escape)",
    okL and resL == nil, tostring(resL))
okL, resL = pcall(FVS, { IsShown = SECRET })
check("FVS: secret IsShown MEMBER value -> nil (defer)",
    okL and resL == nil, tostring(resL))

-- Short-circuit contract: a provably-hidden verdict must never depend on
-- the alpha getter. Once IsShown answered false, GetAlpha lookup/member
-- state is irrelevant — probing it jointly with IsShown would degrade a
-- provable false to nil and park callers that could have acted.
okL, resL = pcall(FVS, lookupThrowFrame({ GetAlpha = true },
    { IsShown = function() return false end }))
check("FVS: hidden + throwing GetAlpha LOOKUP -> false (short-circuit)",
    okL and resL == false, tostring(resL))
okL, resL = pcall(FVS, { IsShown = function() return false end, GetAlpha = SECRET })
check("FVS: hidden + secret GetAlpha MEMBER -> false (short-circuit)",
    okL and resL == false, tostring(resL))

---------------------------------------------------------------------------
-- Stub WoW environment for the anchoring chunk.
---------------------------------------------------------------------------
local scheduled = {}
local inCombat = false

local geomCalls = {}
local function record(name) geomCalls[#geomCalls + 1] = name end
local resetGeom -- assigned after the test frames exist (wipes their points)
local function geomSummary()
    return #geomCalls == 0 and "(none)" or table.concat(geomCalls, ", ")
end
local function sawGeom(needle)
    for _, name in ipairs(geomCalls) do
        if name == needle then return true end
    end
    return false
end

-- Frame stub: records geometry mutations, carries configurable protection
-- and visibility answers (plain value, SECRET sentinel, or a thrower).
-- silent=true (internal frames the chunk CreateFrames itself) skips the
-- recorder so throttle/regen frame Show/Hide noise never pollutes asserts.
local function StubFrame(name, silent)
    local f = {
        __name = name, scripts = {}, hookScripts = {}, events = {},
        shownAnswer = true, alphaAnswer = 1,
        protectedAnswer = false, restrictedAnswer = false,
        points = {},
    }
    local rec = silent and function() end or record
    local function answer(v)
        if type(v) == "function" then return v() end
        return v
    end
    function f:GetObjectType() return "Frame" end
    function f:GetName() return name end
    function f:RegisterEvent(e) self.events[e] = true end
    function f:UnregisterEvent(e) self.events[e] = nil end
    function f:SetScript(which, fn) self.scripts[which] = fn end
    function f:GetScript(which) return self.scripts[which] end
    -- HookScript returns success like the real API
    -- (SimpleScriptRegionAPIDocumentation: Returns success bool); a test can
    -- override this to model a refusing/throwing forbidden frame.
    function f:HookScript(which, fn)
        self.hookScripts[which] = fn
        return true
    end
    function f:IsShown() return answer(self.shownAnswer) end
    function f:GetAlpha() return answer(self.alphaAnswer) end
    function f:SetAlpha(a) self.alphaAnswer = a end
    function f:IsProtected() return answer(self.protectedAnswer) end
    function f:IsAnchoringRestricted() return answer(self.restrictedAnswer) end
    function f:Show() rec(name .. ":Show") end
    function f:Hide() rec(name .. ":Hide") end
    function f:GetNumPoints() return #self.points end
    function f:GetPoint(i)
        local p = self.points[i or 1]
        if p then return p.pt, p.rel, p.relPt, p.x, p.y end
    end
    function f:ClearAllPoints()
        rec(name .. ":ClearAllPoints")
        self.points = {}
    end
    function f:SetPoint(pt, rel, relPt, x, y)
        rec(name .. ":SetPoint")
        self.points = { { pt = pt, rel = rel, relPt = relPt, x = x, y = y } }
    end
    function f:GetWidth() return self.width or 100 end
    function f:GetHeight() return self.height or 100 end
    function f:SetWidth(w) self.width = w end
    function f:SetHeight(h) self.height = h end
    function f:GetEffectiveScale() return 1 end
    function f:GetScale() return 1 end
    function f:SetSize() end
    return f
end

local createdFrames = {}
local env = setmetatable({
    C_Timer = { After = function(_, fn) scheduled[#scheduled + 1] = fn end },
    CreateFrame = function(_, name)
        local f = StubFrame(name or "anon", true)
        createdFrames[#createdFrames + 1] = f
        return f
    end,
    InCombatLockdown = function() return inCombat end,
    hooksecurefunc = function() end,
    issecretvalue = fakeIsSecretValue,
    wipe = function(t) for k in pairs(t) do t[k] = nil end return t end,
}, { __index = _G })
env._G = env
env.UIParent = StubFrame("UIParent", true)

local frameAnchoring = {}
ns.Addon = { db = { profile = { frameAnchoring = frameAnchoring } } }

local ANCHORING = "modules/layout/anchoring.lua"
local chunk = assert(loadstring(readFile(ANCHORING), "@" .. ANCHORING))
setfenv(chunk, env)
chunk("QUI", ns)

assert(type(env.QUI_ApplyFrameAnchor) == "function",
    "anchoring chunk must export _G.QUI_ApplyFrameAnchor")
assert(type(env.QUI_RegisterFrameResolver) == "function",
    "anchoring chunk must export _G.QUI_RegisterFrameResolver")

local function runScheduled()
    -- Drain including timers queued by timers (regen reconcile chains one),
    -- then pump every internal OnUpdate (the ApplyAllFrameAnchors throttle
    -- frame arms itself and disarms on the next OnUpdate tick).
    for _ = 1, 10 do
        if #scheduled == 0 then break end
        local pending = scheduled
        scheduled = {}
        for _, fn in ipairs(pending) do fn() end
    end
    for _, f in ipairs(createdFrames) do
        if f.scripts.OnUpdate then f.scripts.OnUpdate(f) end
    end
end
runScheduled() -- load-time timers (raw-point-mode latch)

-- The real PLAYER_REGEN_ENABLED reconcile frame, captured from load time.
-- Firing its actual handler (instead of calling QUI_ApplyAllFrameAnchors
-- directly) proves the pending latch really was set by the deferred apply:
-- the handler bails when nothing is pending.
local regenFrame
for _, f in ipairs(createdFrames) do
    if f.events["PLAYER_REGEN_ENABLED"] and f.scripts.OnEvent then
        regenFrame = f
        break
    end
end
assert(regenFrame, "anchoring chunk must create a PLAYER_REGEN_ENABLED frame")
local function fireRegen()
    inCombat = false
    regenFrame.scripts.OnEvent(regenFrame, "PLAYER_REGEN_ENABLED")
    runScheduled()
end

-- Test frames + resolvers. The combat child anchors to the screen (sentinel
-- parent, exercises the plain positioning path); the hide child anchors to
-- a parent frame with hideWithParent so the visibility reads run.
local combatChild = StubFrame("combatChild")
local hideChild = StubFrame("hideChild")
local parentFrame = StubFrame("parentFrame")
-- Mutable so a test can swap in a "recreated" parent frame for the same key.
local activeParent = parentFrame

resetGeom = function()
    for i = #geomCalls, 1, -1 do geomCalls[i] = nil end
    -- Wipe stub anchor points so position-match short-circuits
    -- (SmoothSetPoint/FrameAlreadyAtPosition) never mask an apply.
    combatChild.points = {}
    hideChild.points = {}
end
env.QUI_RegisterFrameResolver("qtestCombatChild", { resolver = function() return combatChild end })
env.QUI_RegisterFrameResolver("qtestHideChild", { resolver = function() return hideChild end })
env.QUI_RegisterFrameResolver("qtestParent", { resolver = function() return activeParent end })

frameAnchoring.qtestCombatChild = {
    parent = "screen", point = "CENTER", relative = "CENTER",
    offsetX = 10, offsetY = 20,
}
frameAnchoring.qtestHideChild = {
    parent = "qtestParent", point = "TOP", relative = "BOTTOM",
    offsetX = 0, offsetY = -4, hideWithParent = true,
}

---------------------------------------------------------------------------
-- (a) Combat mutation gate polarity on the resolved frame.
---------------------------------------------------------------------------

-- Baseline out of combat: apply positions the child.
resetGeom()
inCombat = false
env.QUI_ApplyFrameAnchor("qtestCombatChild")
runScheduled()
check("OOC apply repositions combat child",
    sawGeom("combatChild:SetPoint"), geomSummary())

-- Control: a regen fire with NO pending latch must do nothing — this is
-- what makes the later reconcile assertions prove the latch was set.
resetGeom()
fireRegen()
check("regen fire without pending latch applies nothing",
    #geomCalls == 0, geomSummary())

-- In combat, provably-unrestricted frame IS repositioned (gate must not
-- fail-closed on a readable false answer — that polarity matters for the
-- zone-ability reclaim path).
resetGeom()
inCombat = true
combatChild.protectedAnswer = false
combatChild.restrictedAnswer = false
env.QUI_ApplyFrameAnchor("qtestCombatChild")
runScheduled()
check("in-combat apply mutates provably-unrestricted frame",
    sawGeom("combatChild:SetPoint"), geomSummary())

-- In combat, each unprovable/protected answer defers: no geometry at all.
local gateCases = {
    { label = "IsProtected=true", field = "protectedAnswer", value = true },
    { label = "IsProtected=SECRET", field = "protectedAnswer", value = SECRET },
    { label = "IsProtected throws", field = "protectedAnswer",
      value = function() error("secure-context probe") end },
    { label = "IsAnchoringRestricted=SECRET", field = "restrictedAnswer", value = SECRET },
}
for _, case in ipairs(gateCases) do
    combatChild.protectedAnswer = false
    combatChild.restrictedAnswer = false
    combatChild[case.field] = case.value
    resetGeom()
    inCombat = true
    local ok, err = pcall(env.QUI_ApplyFrameAnchor, "qtestCombatChild")
    check(("in-combat %s: apply does not error"):format(case.label), ok, tostring(err))
    check(("in-combat %s: no geometry call reaches frame"):format(case.label),
        #geomCalls == 0, geomSummary())

    -- Regen reconcile: the deferred apply lands once the answer is readable.
    -- fireRegen drives the REAL PLAYER_REGEN_ENABLED handler, which bails
    -- unless the deferred apply latched the pending flag.
    combatChild[case.field] = false
    resetGeom()
    fireRegen()
    check(("post-combat reconcile after %s repositions frame"):format(case.label),
        sawGeom("combatChild:SetPoint"), geomSummary())
end
combatChild.protectedAnswer = false
combatChild.restrictedAnswer = false

---------------------------------------------------------------------------
-- (b) hideWithParent visibility reads.
---------------------------------------------------------------------------
inCombat = false

-- Readable visible parent: child positioned, never hidden.
resetGeom()
parentFrame.shownAnswer = true
parentFrame.alphaAnswer = 1
env.QUI_ApplyFrameAnchor("qtestHideChild")
runScheduled()
check("visible parent: child gets SetPoint",
    sawGeom("hideChild:SetPoint"), geomSummary())
check("visible parent: child not hidden", not sawGeom("hideChild:Hide"), geomSummary())

-- Readable hidden parent: child hidden, latch exposed, no SetPoint.
resetGeom()
parentFrame.shownAnswer = false
env.QUI_ApplyFrameAnchor("qtestHideChild")
runScheduled()
check("hidden parent: child hidden", sawGeom("hideChild:Hide"), geomSummary())
check("hidden parent: no SetPoint on child",
    not sawGeom("hideChild:SetPoint"), geomSummary())
check("hidden parent: QUI_IsFrameHiddenByAnchor latches",
    env.QUI_IsFrameHiddenByAnchor("qtestHideChild") == true)

-- Parent back: child shown again and repositioned.
resetGeom()
parentFrame.shownAnswer = true
env.QUI_ApplyFrameAnchor("qtestHideChild")
runScheduled()
check("parent restored: child shown", sawGeom("hideChild:Show"), geomSummary())
check("parent restored: child repositioned", sawGeom("hideChild:SetPoint"), geomSummary())
check("parent restored: hidden latch cleared",
    env.QUI_IsFrameHiddenByAnchor("qtestHideChild") == false)

-- Alpha ~ 0 counts as hidden (readable number).
resetGeom()
parentFrame.alphaAnswer = 0
env.QUI_ApplyFrameAnchor("qtestHideChild")
runScheduled()
check("alpha~0 parent: child hidden", sawGeom("hideChild:Hide"), geomSummary())
parentFrame.alphaAnswer = 1
env.QUI_ApplyFrameAnchor("qtestHideChild")
runScheduled()

-- Unreadable visibility answers out of combat: the hide/show DECISION
-- defers but the child must still be POSITIONED (otherwise an unreadable
-- parent strands it unanchored forever), the previous latch state must
-- survive untouched, and nothing may error. (Pre-fix behavior: a SECRET
-- IsShown answer is truthy, so the child was hidden/shown as if the state
-- were readable; a throwing getter escaped the apply entirely.)
local visCases = {
    { label = "IsShown=SECRET", field = "shownAnswer", value = SECRET },
    { label = "IsShown throws", field = "shownAnswer",
      value = function() error("secure-context read") end },
    { label = "GetAlpha=SECRET", field = "alphaAnswer", value = SECRET },
    { label = "GetAlpha throws", field = "alphaAnswer",
      value = function() error("secure-context read") end },
}
for _, case in ipairs(visCases) do
    parentFrame.shownAnswer = true
    parentFrame.alphaAnswer = 1
    parentFrame[case.field] = case.value
    resetGeom()
    local ok, err = pcall(env.QUI_ApplyFrameAnchor, "qtestHideChild")
    check(("%s: apply does not error"):format(case.label), ok, tostring(err))
    check(("%s: child still positioned"):format(case.label),
        sawGeom("hideChild:SetPoint"), geomSummary())
    check(("%s: no Hide/Show on child"):format(case.label),
        not sawGeom("hideChild:Hide") and not sawGeom("hideChild:Show"),
        geomSummary())
    check(("%s: hidden latch unchanged"):format(case.label),
        env.QUI_IsFrameHiddenByAnchor("qtestHideChild") == false)
    -- Restore readable and drain the fresh-stack retry so the next case
    -- starts from a clean (readable-pass) latch state.
    parentFrame[case.field] = case.field == "alphaAnswer" and 1 or true
    runScheduled()
end

-- Fresh-stack retry corrects the deferred visibility decision: an
-- unreadable answer schedules ONE C_Timer.After(0) re-apply; when the
-- retry reads a readable-HIDDEN parent, the child gets hidden.
parentFrame.shownAnswer = SECRET
resetGeom()
env.QUI_ApplyFrameAnchor("qtestHideChild")
check("retry pending after unreadable answer", #scheduled > 0,
    ("%d scheduled"):format(#scheduled))
parentFrame.shownAnswer = false
runScheduled()
check("fresh-stack retry hides child once parent readable-hidden",
    sawGeom("hideChild:Hide"), geomSummary())
check("fresh-stack retry sets hidden latch",
    env.QUI_IsFrameHiddenByAnchor("qtestHideChild") == true)
parentFrame.shownAnswer = true
resetGeom()
env.QUI_ApplyFrameAnchor("qtestHideChild")
runScheduled()
check("readable-visible pass restores child after retry cycle",
    sawGeom("hideChild:Show"), geomSummary())

-- Persistently unreadable answer must NOT become a poll loop: the retry is
-- single-shot per unreadable episode. runScheduled drains up to 10 timer
-- generations — an every-frame reschedule would leave the queue non-empty.
parentFrame.shownAnswer = SECRET
resetGeom()
env.QUI_ApplyFrameAnchor("qtestHideChild")
runScheduled()
check("persistent secret: retry queue drains (no poll loop)",
    #scheduled == 0, ("%d still scheduled"):format(#scheduled))
local scheduledBefore = #scheduled
env.QUI_ApplyFrameAnchor("qtestHideChild")
check("persistent secret: repeat apply schedules no further retry",
    #scheduled == scheduledBefore, ("%d scheduled"):format(#scheduled))
-- A readable pass re-arms the retry for the NEXT unreadable episode.
parentFrame.shownAnswer = true
env.QUI_ApplyFrameAnchor("qtestHideChild")
runScheduled()
parentFrame.shownAnswer = SECRET
scheduledBefore = #scheduled
env.QUI_ApplyFrameAnchor("qtestHideChild")
check("readable pass re-arms the single-shot retry",
    #scheduled == scheduledBefore + 1, ("%d scheduled"):format(#scheduled))
runScheduled() -- burn the retry against parentFrame (still secret)

-- The latch is scoped to the PARENT IDENTITY, not just the child key. With
-- the retry burned against parentFrame, a recreated parent frame (same
-- parent key, new frame object) is a NEW episode and must re-arm — a
-- key-only latch would leave the new parent's visibility stale forever.
local parentFrame2 = StubFrame("parentFrame2")
parentFrame2.shownAnswer = SECRET
activeParent = parentFrame2
scheduledBefore = #scheduled
env.QUI_ApplyFrameAnchor("qtestHideChild")
check("recreated parent frame re-arms the retry",
    #scheduled == scheduledBefore + 1, ("%d scheduled"):format(#scheduled))
runScheduled() -- burn it against parentFrame2

-- Same for a settings.parent change to a different key/frame.
local parentFrame3 = StubFrame("parentFrame3")
parentFrame3.shownAnswer = SECRET
env.QUI_RegisterFrameResolver("qtestParent3",
    { resolver = function() return parentFrame3 end })
frameAnchoring.qtestHideChild.parent = "qtestParent3"
scheduledBefore = #scheduled
env.QUI_ApplyFrameAnchor("qtestHideChild")
check("settings.parent change re-arms the retry",
    #scheduled == scheduledBefore + 1, ("%d scheduled"):format(#scheduled))
runScheduled() -- burn it against parentFrame3

-- Bulk re-apply (profile/spec switch path) wipes the latch table with the
-- rest of the runtime state, so every key re-arms.
scheduledBefore = #scheduled
env.QUI_ApplyAllFrameAnchors(true)
check("bulk re-apply re-arms the retry (latch wiped)",
    #scheduled > scheduledBefore, ("%d scheduled"):format(#scheduled))
runScheduled()
check("bulk re-apply retry still drains (no poll loop)",
    #scheduled == 0, ("%d still scheduled"):format(#scheduled))

-- And the retry against the NEW parent corrects visibility once readable:
-- the burned latch belongs to parentFrame3, whose answer turning readable-
-- hidden must hide the child on the next apply.
parentFrame3.shownAnswer = false
resetGeom()
env.QUI_ApplyFrameAnchor("qtestHideChild")
runScheduled()
check("new parent readable-hidden hides child after latch episodes",
    sawGeom("hideChild:Hide"), geomSummary())

-- Restore the original topology for the in-combat block below.
frameAnchoring.qtestHideChild.parent = "qtestParent"
activeParent = parentFrame
parentFrame.shownAnswer = true
parentFrame.alphaAnswer = 1
resetGeom()
env.QUI_ApplyFrameAnchor("qtestHideChild")
runScheduled()

-- In-combat unreadable visibility latches the regen reconcile: once the
-- parent is readable again, the reconcile pass repositions the child.
parentFrame.shownAnswer = SECRET
inCombat = true
resetGeom()
local okCombatVis, errCombatVis = pcall(env.QUI_ApplyFrameAnchor, "qtestHideChild")
check("in-combat secret visibility: apply does not error",
    okCombatVis, tostring(errCombatVis))
check("in-combat secret visibility: no mutation", #geomCalls == 0, geomSummary())
parentFrame.shownAnswer = true
resetGeom()
fireRegen()
check("post-combat reconcile repositions hide child",
    sawGeom("hideChild:SetPoint"), geomSummary())

---------------------------------------------------------------------------
-- (d) Chain-walk visibility reads (ResolveParentFrame). The plain anchored
--     path (no hideWithParent) truth-tested the parent's raw IsShown()
--     answer: a throwing getter ESCAPED QUI_ApplyFrameAnchor and a secret
--     answer walked (or refused to walk) the chain on a guess. The fixed
--     path reads through FrameVisibleSecure: readable answers keep the old
--     chain-walk behavior, unreadable answers keep the CONFIGURED parent
--     (never walk on a guess) and re-evaluate on a fresh stack / at regen.
---------------------------------------------------------------------------
inCombat = false

local chainChild = StubFrame("chainChild")
local grandparent = StubFrame("grandparent")
env.QUI_RegisterFrameResolver("qtestChainChild",
    { resolver = function() return chainChild end })
env.QUI_RegisterFrameResolver("qtestGrandparent",
    { resolver = function() return grandparent end })
frameAnchoring.qtestChainChild = {
    parent = "qtestParent", point = "TOP", relative = "BOTTOM",
    offsetX = 0, offsetY = -6,
}
-- Gives the hidden parent a configured chain link to walk up to.
frameAnchoring.qtestParent = {
    parent = "qtestGrandparent", point = "CENTER", relative = "CENTER",
    offsetX = 0, offsetY = 0,
}

local function chainRel()
    local _, rel = chainChild:GetPoint(1)
    return rel
end

-- Readable-shown parent: child anchors to the configured parent.
parentFrame.shownAnswer = true
chainChild.points = {}
resetGeom()
env.QUI_ApplyFrameAnchor("qtestChainChild")
runScheduled()
check("chain: visible parent anchors child to parent",
    chainRel() == parentFrame, tostring(chainRel() and chainRel().__name))

-- Readable-hidden parent: the walk proceeds to the grandparent.
parentFrame.shownAnswer = false
chainChild.points = {}
resetGeom()
env.QUI_ApplyFrameAnchor("qtestChainChild")
runScheduled()
check("chain: readable-hidden parent walks to grandparent",
    chainRel() == grandparent, tostring(chainRel() and chainRel().__name))

-- Secret IsShown: no error, NO walk on a guess (configured parent kept),
-- ONE fresh-stack retry armed; a persistent secret never becomes a poll.
parentFrame.shownAnswer = SECRET
chainChild.points = {}
resetGeom()
local schedBefore = #scheduled
local okChain, errChain = pcall(env.QUI_ApplyFrameAnchor, "qtestChainChild")
check("chain: secret IsShown does not error", okChain, tostring(errChain))
check("chain: secret IsShown keeps configured parent (no walk on guess)",
    chainRel() == parentFrame, tostring(chainRel() and chainRel().__name))
check("chain: secret IsShown arms one retry",
    #scheduled == schedBefore + 1, ("%d scheduled"):format(#scheduled))
runScheduled() -- burn the retry (answer still secret)
check("chain: persistent secret drains (no poll loop)",
    #scheduled == 0, ("%d still scheduled"):format(#scheduled))
schedBefore = #scheduled
env.QUI_ApplyFrameAnchor("qtestChainChild")
check("chain: repeat apply schedules no further retry",
    #scheduled == schedBefore, ("%d scheduled"):format(#scheduled))

-- Readable pass re-arms; a THROWING getter must not escape the apply.
parentFrame.shownAnswer = true
env.QUI_ApplyFrameAnchor("qtestChainChild")
runScheduled()
parentFrame.shownAnswer = function() error("secure-context read") end
chainChild.points = {}
okChain, errChain = pcall(env.QUI_ApplyFrameAnchor, "qtestChainChild")
check("chain: throwing IsShown does not escape QUI_ApplyFrameAnchor",
    okChain, tostring(errChain))
check("chain: throwing IsShown keeps configured parent",
    chainRel() == parentFrame, tostring(chainRel() and chainRel().__name))

-- The armed retry corrects the resolution once the answer is readable:
-- a readable-hidden parent now walks to the grandparent.
parentFrame.shownAnswer = false
runScheduled()
check("chain: fresh-stack retry walks once parent readable-hidden",
    chainRel() == grandparent, tostring(chainRel() and chainRel().__name))

-- MULTI-LINK: a readable-hidden link followed by a persistently-unreadable
-- deeper link must NOT re-arm the retry every pass (the mid-walk readable
-- answer used to clear the latch each time — endless zero-delay loop).
parentFrame.shownAnswer = false     -- readable-hidden: walk continues
grandparent.shownAnswer = SECRET    -- unreadable second link
chainChild.points = {}
resetGeom()
schedBefore = #scheduled
env.QUI_ApplyFrameAnchor("qtestChainChild")
check("multi-link: unreadable deep link arms one retry",
    #scheduled == schedBefore + 1, ("%d scheduled"):format(#scheduled))
runScheduled()
check("multi-link: persistent deep secret drains (no zero-delay loop)",
    #scheduled == 0, ("%d still scheduled"):format(#scheduled))
schedBefore = #scheduled
env.QUI_ApplyFrameAnchor("qtestChainChild")
check("multi-link: repeat apply schedules no further retry",
    #scheduled == schedBefore, ("%d scheduled"):format(#scheduled))
-- A fully-readable resolution ends the episode and re-arms for the next.
grandparent.shownAnswer = true
env.QUI_ApplyFrameAnchor("qtestChainChild")
runScheduled()
grandparent.shownAnswer = SECRET
schedBefore = #scheduled
env.QUI_ApplyFrameAnchor("qtestChainChild")
check("multi-link: fully-readable pass re-arms the retry",
    #scheduled == schedBefore + 1, ("%d scheduled"):format(#scheduled))
runScheduled() -- burn it
grandparent.shownAnswer = true

-- In combat an unreadable chain link latches the regen reconcile.
parentFrame.shownAnswer = SECRET
inCombat = true
chainChild.points = {}
resetGeom()
okChain, errChain = pcall(env.QUI_ApplyFrameAnchor, "qtestChainChild")
check("chain: in-combat secret visibility does not error",
    okChain, tostring(errChain))
check("chain: in-combat unreadable link defers the WHOLE apply (no mutation)",
    #geomCalls == 0, geomSummary())
parentFrame.shownAnswer = false
chainChild.points = {}
resetGeom()
fireRegen()
check("chain: regen reconcile re-resolves once readable",
    chainRel() == grandparent, tostring(chainRel() and chainRel().__name))

---------------------------------------------------------------------------
-- (e) Throttle coalescing: a request landing while the once-per-frame
--     throttle is armed must replay on the next frame — dropping it loses
--     the state change (visibility flip) that triggered it.
---------------------------------------------------------------------------
inCombat = false
parentFrame.shownAnswer = true
parentFrame.alphaAnswer = 1
env.QUI_ApplyFrameAnchor("qtestHideChild")
runScheduled() -- clean latch state, throttle disarmed

env.QUI_ApplyAllFrameAnchors()  -- applies now, arms the throttle
parentFrame.shownAnswer = false -- visibility flips within the same frame
resetGeom()
env.QUI_ApplyAllFrameAnchors()  -- throttled: must coalesce, not drop
check("throttled call performs no immediate apply",
    #geomCalls == 0, geomSummary())
runScheduled()                  -- next-frame OnUpdate replays the request
check("coalesced replay applies the visibility flip",
    sawGeom("hideChild:Hide"), geomSummary())

---------------------------------------------------------------------------
-- (f) Visible chain parents get visibility hooks: the first hide after a
--     visible resolution must re-run the anchor pass so children walk past
--     the now-hidden link — without the hook the stale chain persisted
--     until another explicit reapply.
---------------------------------------------------------------------------
inCombat = false
local hookParent = StubFrame("hookParent")
local hookChild = StubFrame("hookChild")
env.QUI_RegisterFrameResolver("qtestHookParent",
    { resolver = function() return hookParent end })
env.QUI_RegisterFrameResolver("qtestHookChild",
    { resolver = function() return hookChild end })
frameAnchoring.qtestHookChild = {
    parent = "qtestHookParent", point = "TOP", relative = "BOTTOM",
    offsetX = 0, offsetY = -6,
}
frameAnchoring.qtestHookParent = {
    parent = "qtestGrandparent", point = "CENTER", relative = "CENTER",
    offsetX = 0, offsetY = 0,
}
local function hookChildRel()
    local _, rel = hookChild:GetPoint(1)
    return rel
end

hookParent.shownAnswer = true
env.QUI_ApplyFrameAnchor("qtestHookChild")
runScheduled()
check("hook: visible parent anchors child to parent",
    hookChildRel() == hookParent,
    tostring(hookChildRel() and hookChildRel().__name))
check("hook: visible chain parent receives a visibility hook",
    hookParent.hookScripts.OnHide ~= nil, "no OnHide hook installed")

-- The hook re-runs the anchor pass: the child walks past the hidden parent.
hookParent.shownAnswer = false
if hookParent.hookScripts.OnHide then
    hookParent.hookScripts.OnHide(hookParent)
end
runScheduled()
check("hook: hide after a visible resolution re-anchors child past parent",
    hookChildRel() == grandparent,
    tostring(hookChildRel() and hookChildRel().__name))

---------------------------------------------------------------------------
-- (g) Unreadable-link retries replay the CALLER'S operation: the
--     position-only entry point must not be retried via the full
--     QUI_ApplyFrameAnchor apply (which runs auto-sizing — exactly what
--     that entry point exists to avoid).
---------------------------------------------------------------------------
local posParent = StubFrame("posParent")
local posChild = StubFrame("posChild")
env.QUI_RegisterFrameResolver("qtestPosParent",
    { resolver = function() return posParent end })
env.QUI_RegisterFrameResolver("qtestPosChild",
    { resolver = function() return posChild end })
frameAnchoring.qtestPosChild = {
    parent = "qtestPosParent", point = "TOP", relative = "BOTTOM",
    offsetX = 0, offsetY = -6,
}
assert(type(env.QUI_ReanchorFramePositionOnly) == "function",
    "anchoring chunk must export _G.QUI_ReanchorFramePositionOnly")

local posOnlyCalls, fullApplyCalls = 0, 0
local realPosOnly = env.QUI_ReanchorFramePositionOnly
local realFullApply = env.QUI_ApplyFrameAnchor
env.QUI_ReanchorFramePositionOnly = function(k)
    posOnlyCalls = posOnlyCalls + 1
    return realPosOnly(k)
end
env.QUI_ApplyFrameAnchor = function(k)
    fullApplyCalls = fullApplyCalls + 1
    return realFullApply(k)
end

posParent.shownAnswer = SECRET
schedBefore = #scheduled
env.QUI_ReanchorFramePositionOnly("qtestPosChild")
check("position-only: unreadable link arms one retry",
    #scheduled == schedBefore + 1, ("%d scheduled"):format(#scheduled))
check("position-only: unreadable parent receives a visibility hook",
    posParent.hookScripts.OnHide ~= nil, "no OnHide hook installed")
posOnlyCalls, fullApplyCalls = 0, 0
runScheduled()
check("position-only retry replays the position-only operation",
    posOnlyCalls == 1, ("%d position-only calls"):format(posOnlyCalls))
check("position-only retry does NOT run the full apply",
    fullApplyCalls == 0, ("%d full-apply calls"):format(fullApplyCalls))
env.QUI_ReanchorFramePositionOnly = realPosOnly
env.QUI_ApplyFrameAnchor = realFullApply

---------------------------------------------------------------------------
-- (h) Retry-latch collision: DIFFERENT consumers hitting the SAME
--     unreadable (originKey, frame) episode must EACH get their retry.
--     A shared slot let the first consumer suppress the others — the
--     overlay stayed stale on the hidden parent while position-only
--     corrected itself.
---------------------------------------------------------------------------
inCombat = false
local colParent = StubFrame("colParent")
local colChild = StubFrame("colChild")
local colOverlay = StubFrame("colOverlay")
env.QUI_RegisterFrameResolver("qtestColParent",
    { resolver = function() return colParent end })
env.QUI_RegisterFrameResolver("qtestColChild",
    { resolver = function() return colChild end })
frameAnchoring.qtestColChild = {
    parent = "qtestColParent", point = "TOP", relative = "BOTTOM",
    offsetX = 0, offsetY = -6,
}
assert(type(env.QUI_AnchorOverlayToParent) == "function",
    "anchoring chunk must export _G.QUI_AnchorOverlayToParent")

local overlayCalls = 0
posOnlyCalls, fullApplyCalls = 0, 0
local realOverlay = env.QUI_AnchorOverlayToParent
env.QUI_ReanchorFramePositionOnly = function(k)
    posOnlyCalls = posOnlyCalls + 1
    return realPosOnly(k)
end
env.QUI_ApplyFrameAnchor = function(k)
    fullApplyCalls = fullApplyCalls + 1
    return realFullApply(k)
end
env.QUI_AnchorOverlayToParent = function(o, k, w, h)
    overlayCalls = overlayCalls + 1
    return realOverlay(o, k, w, h)
end

colParent.shownAnswer = SECRET
schedBefore = #scheduled
env.QUI_ReanchorFramePositionOnly("qtestColChild")
env.QUI_AnchorOverlayToParent(colOverlay, "qtestColChild")
check("collision: two consumers arm two independent retries",
    #scheduled == schedBefore + 2, ("%d scheduled"):format(#scheduled))

-- Both replays run their OWN operation once the answer is readable.
colParent.shownAnswer = false
posOnlyCalls, fullApplyCalls, overlayCalls = 0, 0, 0
runScheduled()
check("collision: position-only retry replays position-only",
    posOnlyCalls == 1, ("%d position-only calls"):format(posOnlyCalls))
check("collision: overlay retry replays the overlay anchoring",
    overlayCalls == 1, ("%d overlay calls"):format(overlayCalls))
check("collision: neither retry runs the full apply",
    fullApplyCalls == 0, ("%d full-apply calls"):format(fullApplyCalls))
local _, colOverlayRel = colOverlay:GetPoint(1)
check("collision: overlay replay repositions the overlay",
    colOverlayRel ~= nil, "overlay has no point after replay")

-- Loop safety per consumer slot: a persistently-unreadable episode burns
-- each slot ONCE; repeat calls arm nothing further.
colParent.shownAnswer = SECRET
env.QUI_ReanchorFramePositionOnly("qtestColChild")
env.QUI_AnchorOverlayToParent(colOverlay, "qtestColChild")
runScheduled() -- replays re-enter while still secret; slots stay burned
check("collision: persistent secret drains (no per-consumer poll loop)",
    #scheduled == 0, ("%d still scheduled"):format(#scheduled))
schedBefore = #scheduled
env.QUI_ReanchorFramePositionOnly("qtestColChild")
env.QUI_AnchorOverlayToParent(colOverlay, "qtestColChild")
check("collision: repeat calls schedule no further retries",
    #scheduled == schedBefore, ("%d scheduled"):format(#scheduled))
env.QUI_ReanchorFramePositionOnly = realPosOnly
env.QUI_ApplyFrameAnchor = realFullApply
env.QUI_AnchorOverlayToParent = realOverlay

---------------------------------------------------------------------------
-- (i) Retry replays the NEWEST arguments: a repeat call before the timer
--     fires must refresh the slot's stored operation. Storing the first
--     closure let the replay overwrite newer overlay geometry with the
--     first call's captured dimensions.
---------------------------------------------------------------------------
-- Fresh episode: a readable pass clears the burned slots from (h).
colParent.shownAnswer = true
env.QUI_AnchorOverlayToParent(colOverlay, "qtestColChild")
runScheduled()

colParent.shownAnswer = SECRET
schedBefore = #scheduled
env.QUI_AnchorOverlayToParent(colOverlay, "qtestColChild", 10, 11)
env.QUI_AnchorOverlayToParent(colOverlay, "qtestColChild", 20, 21)
check("stale-args: repeat overlay call arms only one retry",
    #scheduled == schedBefore + 1, ("%d scheduled"):format(#scheduled))
check("stale-args: direct calls applied the newest dimensions",
    colOverlay.width == 20 and colOverlay.height == 21,
    ("%sx%s"):format(tostring(colOverlay.width), tostring(colOverlay.height)))

colParent.shownAnswer = false
runScheduled()
check("stale-args: retry replays the NEWEST dimensions, not the first call's",
    colOverlay.width == 20 and colOverlay.height == 21,
    ("%sx%s"):format(tostring(colOverlay.width), tostring(colOverlay.height)))

---------------------------------------------------------------------------
-- (j) Queued retry vs a newer READABLE call: the parent turning readable
--     (episode cleared, current geometry applied) between arm and fire
--     must DEFUSE the pending timer — its captured slot table is detached,
--     and replaying the stored op would overwrite the newer geometry with
--     stale arguments.
---------------------------------------------------------------------------
colParent.shownAnswer = SECRET
schedBefore = #scheduled
env.QUI_AnchorOverlayToParent(colOverlay, "qtestColChild", 31, 32)
check("readable-race: secret call arms one retry",
    #scheduled == schedBefore + 1, ("%d scheduled"):format(#scheduled))

colParent.shownAnswer = true  -- readable BEFORE the timer fires
env.QUI_AnchorOverlayToParent(colOverlay, "qtestColChild", 41, 42)
check("readable-race: readable call applies the newer dimensions",
    colOverlay.width == 41 and colOverlay.height == 42,
    ("%sx%s"):format(tostring(colOverlay.width), tostring(colOverlay.height)))

runScheduled() -- the stale timer fires and must detect its detached slot
check("readable-race: detached retry does NOT overwrite newer geometry",
    colOverlay.width == 41 and colOverlay.height == 42,
    ("%sx%s"):format(tostring(colOverlay.width), tostring(colOverlay.height)))

---------------------------------------------------------------------------
-- (k) Wipe race: ApplyAllFrameAnchors wipes the latch between arm and
--     fire. The detached timer's captured slot table still HOLDS its op
--     (the wipe empties the outer latch only), so only the table-identity
--     liveness check stands between it and replaying stale geometry over
--     a newer readable call.
---------------------------------------------------------------------------
colParent.shownAnswer = SECRET
env.QUI_AnchorOverlayToParent(colOverlay, "qtestColChild", 31, 32)
env.QUI_ApplyAllFrameAnchors() -- immediate (throttle idle): wipes the latch
colParent.shownAnswer = true
env.QUI_AnchorOverlayToParent(colOverlay, "qtestColChild", 41, 42)
runScheduled() -- detached timer fires; must not replay 31x32
check("wipe-race: detached retry does NOT overwrite newer geometry",
    colOverlay.width == 41 and colOverlay.height == 42,
    ("%sx%s"):format(tostring(colOverlay.width), tostring(colOverlay.height)))

---------------------------------------------------------------------------
-- (l) Replacement-parent race: the resolver swaps the chain-link frame
--     between two unreadable calls. Parent A's still-live timer must not
--     replay its stale op — worse, that replay re-enters the walk and
--     REFRESHES parent B's pending slot with the OLD arguments, so the
--     stale geometry wins even after B's own timer fires.
---------------------------------------------------------------------------
local colParent2 = StubFrame("colParent2")
local colParentLive = colParent
env.QUI_RegisterFrameResolver("qtestColParent",
    { resolver = function() return colParentLive end })

colParent.shownAnswer = SECRET
colParent2.shownAnswer = SECRET
schedBefore = #scheduled
env.QUI_AnchorOverlayToParent(colOverlay, "qtestColChild", 51, 52)
check("replacement-race: first unreadable parent arms one retry",
    #scheduled == schedBefore + 1, ("%d scheduled"):format(#scheduled))

colParentLive = colParent2 -- resolver now returns the replacement parent
env.QUI_AnchorOverlayToParent(colOverlay, "qtestColChild", 61, 62)
check("replacement-race: replacement parent refreshes the pending retry",
    #scheduled == schedBefore + 1, ("%d scheduled"):format(#scheduled))
check("replacement-race: direct call applied the newest dimensions",
    colOverlay.width == 61 and colOverlay.height == 62,
    ("%sx%s"):format(tostring(colOverlay.width), tostring(colOverlay.height)))

runScheduled() -- the retry replays the NEWEST op, never parent A's stale one
check("replacement-race: stale parent-A retry does NOT win",
    colOverlay.width == 61 and colOverlay.height == 62,
    ("%sx%s"):format(tostring(colOverlay.width), tostring(colOverlay.height)))
check("replacement-race: timers drain (no flip-flop loop)",
    #scheduled == 0, ("%d still scheduled"):format(#scheduled))

---------------------------------------------------------------------------
-- (m) A→B→A flip-flop keeps the NEWEST retry alive: burning per-frame
--     slots dropped the third call's retry outright (A's slot already
--     burned, B's invalidated) — the newest geometry then had NO
--     fresh-stack correction at all.
---------------------------------------------------------------------------
-- End the previous episode with a readable pass, then go unreadable again.
colParent2.shownAnswer = true
env.QUI_AnchorOverlayToParent(colOverlay, "qtestColChild")
runScheduled()

env.QUI_AnchorOverlayToParent = function(o, k, w, h)
    overlayCalls = overlayCalls + 1
    return realOverlay(o, k, w, h)
end
colParent.shownAnswer = SECRET
colParent2.shownAnswer = SECRET
colParentLive = colParent
env.QUI_AnchorOverlayToParent(colOverlay, "qtestColChild", 71, 72) -- arm on A
colParentLive = colParent2
env.QUI_AnchorOverlayToParent(colOverlay, "qtestColChild", 81, 82) -- refresh (B)
colParentLive = colParent
env.QUI_AnchorOverlayToParent(colOverlay, "qtestColChild", 91, 92) -- refresh (A again)
overlayCalls = 0
runScheduled()
check("flip-flop: the newest call still gets its fresh-stack retry",
    overlayCalls >= 1, ("%d overlay replays"):format(overlayCalls))
check("flip-flop: retry replays the NEWEST dimensions",
    colOverlay.width == 91 and colOverlay.height == 92,
    ("%sx%s"):format(tostring(colOverlay.width), tostring(colOverlay.height)))
check("flip-flop: timers drain (no chained loop)",
    #scheduled == 0, ("%d still scheduled"):format(#scheduled))

---------------------------------------------------------------------------
-- (n) screen/disabled race: the parent changes to "screen" while a retry
--     is queued. The screen/disabled early return is a fully-readable
--     resolution and must end the retry episode — without the clear, the
--     stale timer replays old geometry over the newer screen resolution.
---------------------------------------------------------------------------
-- Fresh episode: a readable pass clears (m)'s burned-frame state.
colParent.shownAnswer = true
env.QUI_AnchorOverlayToParent(colOverlay, "qtestColChild")
runScheduled()

colParent.shownAnswer = SECRET
schedBefore = #scheduled
env.QUI_AnchorOverlayToParent(colOverlay, "qtestColChild", 111, 112)
check("screen-race: unreadable parent arms one retry",
    #scheduled == schedBefore + 1, ("%d scheduled"):format(#scheduled))
frameAnchoring.qtestColChild.parent = "screen"
env.QUI_AnchorOverlayToParent(colOverlay, "qtestColChild", 121, 122)
check("screen-race: screen resolution applies the newest dimensions",
    colOverlay.width == 121 and colOverlay.height == 122,
    ("%sx%s"):format(tostring(colOverlay.width), tostring(colOverlay.height)))
runScheduled() -- stale timer must detect its cleared state and skip
check("screen-race: stale retry does NOT overwrite the screen resolution",
    colOverlay.width == 121 and colOverlay.height == 122,
    ("%sx%s"):format(tostring(colOverlay.width), tostring(colOverlay.height)))
frameAnchoring.qtestColChild.parent = "qtestColParent"
env.QUI_AnchorOverlayToParent = realOverlay

---------------------------------------------------------------------------
-- (o) Consumer op STARTED in combat: position-only must be latched and the
--     regen reconcile must replay exactly it — NOT substitute the
--     auto-sizing bulk apply (repro: width 77 → 333) and NOT drop it.
---------------------------------------------------------------------------
local Anchoring = ns.QUI_Anchoring
local bulkApplies = 0
local realBulk = Anchoring.ApplyAllFrameAnchors
Anchoring.ApplyAllFrameAnchors = function(self, ...)
    bulkApplies = bulkApplies + 1
    return realBulk(self, ...)
end
env.QUI_ReanchorFramePositionOnly = function(k)
    posOnlyCalls = posOnlyCalls + 1
    return realPosOnly(k)
end

posParent.shownAnswer = true
posChild.points = {}
inCombat = true
posOnlyCalls, bulkApplies = 0, 0
env.QUI_ReanchorFramePositionOnly("qtestPosChild")
check("combat-start: in-combat position-only makes no immediate geometry call",
    select(2, posChild:GetPoint(1)) == nil, "posChild has a point")
fireRegen()
check("combat-start: regen drain replays the latched position-only op",
    posOnlyCalls >= 1, ("%d position-only calls"):format(posOnlyCalls))
check("combat-start: regen does NOT substitute the bulk apply for a lone consumer op",
    bulkApplies == 0, ("%d bulk applies"):format(bulkApplies))
local _, posRel = posChild:GetPoint(1)
check("combat-start: replayed op repositions the frame",
    posRel == posParent, tostring(posRel and posRel.__name))

-- Drained: a second regen fires nothing further.
posOnlyCalls, bulkApplies = 0, 0
fireRegen()
check("combat-start: latch drains (second regen replays nothing)",
    posOnlyCalls == 0 and bulkApplies == 0,
    ("%d pos-only, %d bulk"):format(posOnlyCalls, bulkApplies))

---------------------------------------------------------------------------
-- (p) Retry timer CROSSES into combat: the armed consumer op must be
--     latched for the regen drain (not swapped for the bulk-apply flag)
--     and must replay its newest arguments after combat.
---------------------------------------------------------------------------
overlayCalls = 0
env.QUI_AnchorOverlayToParent = function(o, k, w, h)
    overlayCalls = overlayCalls + 1
    return realOverlay(o, k, w, h)
end

inCombat = false
colParent.shownAnswer = true
colParentLive = colParent
env.QUI_AnchorOverlayToParent(colOverlay, "qtestColChild") -- readable pass: fresh episode
runScheduled()

colParent.shownAnswer = SECRET
env.QUI_AnchorOverlayToParent(colOverlay, "qtestColChild", 131, 132) -- arms retry
inCombat = true
runScheduled() -- timer fires IN combat: must latch the overlay op
colParent.shownAnswer = true
overlayCalls, bulkApplies = 0, 0
fireRegen()
check("combat-cross: regen drain replays the overlay op",
    overlayCalls >= 1, ("%d overlay calls"):format(overlayCalls))
check("combat-cross: lone overlay op does not trigger the bulk apply",
    bulkApplies == 0, ("%d bulk applies"):format(bulkApplies))
check("combat-cross: replay applies the armed call's dimensions",
    colOverlay.width == 131 and colOverlay.height == 132,
    ("%sx%s"):format(tostring(colOverlay.width), tostring(colOverlay.height)))
Anchoring.ApplyAllFrameAnchors = realBulk

---------------------------------------------------------------------------
-- (q) Bulk apply REPLAYS the consumer retries it wipes: an unrelated
--     ApplyAllFrameAnchors (visibility callback, module refresh) between
--     arm and fire must not silently drop a pending overlay retry. No
--     newer consumer call afterward — the replay must come from the bulk
--     pass itself.
---------------------------------------------------------------------------
inCombat = false
colParent.shownAnswer = SECRET
env.QUI_AnchorOverlayToParent(colOverlay, "qtestColChild", 141, 142) -- arms retry
colOverlay.width, colOverlay.height = 0, 0
colParent.shownAnswer = true
overlayCalls = 0
env.QUI_ApplyAllFrameAnchors() -- wipes the latch; must harvest + replay the op
check("wipe-replay: bulk apply replays the harvested overlay op",
    overlayCalls >= 1, ("%d overlay calls"):format(overlayCalls))
check("wipe-replay: replayed op restores the overlay geometry",
    colOverlay.width == 141 and colOverlay.height == 142,
    ("%sx%s"):format(tostring(colOverlay.width), tostring(colOverlay.height)))
runScheduled()
check("wipe-replay: timers drain after the replay",
    #scheduled == 0, ("%d still scheduled"):format(#scheduled))
env.QUI_AnchorOverlayToParent = realOverlay
env.QUI_ReanchorFramePositionOnly = realPosOnly

---------------------------------------------------------------------------
-- (r) Hard episode cap: a resolver that returns a FRESH unreadable frame
--     every call defeats the per-frame-identity burn — the arm counter
--     must still bound the retry chain.
---------------------------------------------------------------------------
local freshCount = 0
local freshChild = StubFrame("freshChild")
env.QUI_RegisterFrameResolver("qtestFreshParent", { resolver = function()
    freshCount = freshCount + 1
    local f = StubFrame("fresh" .. freshCount, true)
    f.shownAnswer = SECRET
    return f
end })
env.QUI_RegisterFrameResolver("qtestFreshChild",
    { resolver = function() return freshChild end })
frameAnchoring.qtestFreshChild = {
    parent = "qtestFreshParent", point = "TOP", relative = "BOTTOM",
    offsetX = 0, offsetY = -6,
}
env.QUI_ReanchorFramePositionOnly("qtestFreshChild")
local capRounds = 0
while #scheduled > 0 and capRounds < 40 do
    capRounds = capRounds + 1
    runScheduled()
end
check("fresh-frame cap: retry chain terminates",
    #scheduled == 0, ("%d still scheduled after %d rounds"):format(#scheduled, capRounds))
check("fresh-frame cap: arms are hard-bounded",
    freshCount <= 40, ("%d resolver calls"):format(freshCount))

---------------------------------------------------------------------------
-- (s) Visibility-hook success tracking: HookScript RETURNS success and can
--     refuse (forbidden ScriptBindings aspect) or throw. A failed install
--     must NOT permanently mark the frame hooked — the next resolution
--     retries and installs once the frame accepts.
---------------------------------------------------------------------------
inCombat = false
local hookyParent = StubFrame("hookyParent")
local hookyChild = StubFrame("hookyChild")
local hookMode = "refuse" -- "refuse" | "throw" | "accept"
hookyParent.HookScript = function(self, which, fn)
    if hookMode == "refuse" then return false end
    if hookMode == "throw" then error("forbidden script bindings") end
    self.hookScripts[which] = fn
    return true
end
env.QUI_RegisterFrameResolver("qtestHookyParent",
    { resolver = function() return hookyParent end })
env.QUI_RegisterFrameResolver("qtestHookyChild",
    { resolver = function() return hookyChild end })
frameAnchoring.qtestHookyChild = {
    parent = "qtestHookyParent", point = "TOP", relative = "BOTTOM",
    offsetX = 0, offsetY = -6,
}

env.QUI_ApplyFrameAnchor("qtestHookyChild")
runScheduled()
check("hook-verify: refused HookScript records no hook",
    hookyParent.hookScripts.OnHide == nil, "OnHide recorded despite refusal")

hookMode = "throw"
local okThrow, errThrow = pcall(env.QUI_ApplyFrameAnchor, "qtestHookyChild")
runScheduled()
check("hook-verify: throwing HookScript is contained", okThrow, tostring(errThrow))

hookMode = "accept"
env.QUI_ApplyFrameAnchor("qtestHookyChild")
runScheduled()
check("hook-verify: later acceptance installs the visibility hooks",
    hookyParent.hookScripts.OnShow ~= nil and hookyParent.hookScripts.OnHide ~= nil,
    "hooks missing after acceptance")

---------------------------------------------------------------------------
-- (t) MIXED full-apply + pending positionOnly: the bulk pass must NOT
--     auto-size an origin whose pending consumer op is position-only
--     (module-owned geometry, repro: width 77 → 333) while UNRELATED keys
--     still auto-size (88 → 444). Covers BOTH pending-op stores: the armed
--     retry state (harvested by ApplyAllFrameAnchors) and the combat latch
--     (drained by the regen reconcile right after its bulk apply).
---------------------------------------------------------------------------
inCombat = false
frameAnchoring.qtestPosChild.autoWidth = true
posParent.width = 333
local sizeParent = StubFrame("sizeParent")
local sizeChild = StubFrame("sizeChild")
env.QUI_RegisterFrameResolver("qtestSizeParent",
    { resolver = function() return sizeParent end })
env.QUI_RegisterFrameResolver("qtestSizeChild",
    { resolver = function() return sizeChild end })
frameAnchoring.qtestSizeChild = {
    parent = "qtestSizeParent", point = "TOP", relative = "BOTTOM",
    offsetX = 0, offsetY = 0, autoWidth = true,
}
sizeParent.width = 444
sizeParent.shownAnswer = true

env.QUI_ReanchorFramePositionOnly = function(k)
    posOnlyCalls = posOnlyCalls + 1
    return realPosOnly(k)
end

-- Retry-store path: an armed positionOnly retry pends while an unrelated
-- bulk apply runs.
posParent.shownAnswer = SECRET
posChild.width = 77
sizeChild.width = 88
env.QUI_ReanchorFramePositionOnly("qtestPosChild") -- arms the retry
posParent.shownAnswer = true
posOnlyCalls = 0
env.QUI_ApplyAllFrameAnchors()
check("mixed-bulk: bulk pass replays the pending position-only op",
    posOnlyCalls >= 1, ("%d position-only calls"):format(posOnlyCalls))
check("mixed-bulk: same-origin positionOnly key is NOT auto-sized",
    posChild.width == 77, ("width %s"):format(tostring(posChild.width)))
check("mixed-bulk: unrelated key still auto-sizes",
    sizeChild.width == 444, ("width %s"):format(tostring(sizeChild.width)))
runScheduled()

-- Combat-latch path: a positionOnly op latched in combat plus a deferred
-- full apply — the regen bulk apply must size the unrelated key only.
inCombat = true
posChild.width = 77
sizeChild.width = 88
env.QUI_ReanchorFramePositionOnly("qtestPosChild") -- latches the combat op
sizeChild.protectedAnswer = true
env.QUI_ApplyFrameAnchor("qtestSizeChild") -- restricted: sets the bulk flag
sizeChild.protectedAnswer = false
posOnlyCalls = 0
fireRegen()
check("mixed-regen: regen drain replays the latched position-only op",
    posOnlyCalls >= 1, ("%d position-only calls"):format(posOnlyCalls))
check("mixed-regen: same-origin positionOnly key is NOT auto-sized",
    posChild.width == 77, ("width %s"):format(tostring(posChild.width)))
check("mixed-regen: unrelated key still auto-sizes",
    sizeChild.width == 444, ("width %s"):format(tostring(sizeChild.width)))
check("mixed-regen: suppression is bulk-pass-scoped, not permanent",
    (function()
        env.QUI_ApplyFrameAnchor("qtestPosChild")
        return posChild.width == 333
    end)(), ("width %s"):format(tostring(posChild.width)))

---------------------------------------------------------------------------
-- (u) THROTTLE-ARMED regen: when the combat reconcile's full apply is
--     coalesced onto the throttle replay, its positionOnly consumer must
--     remain pending until that replay has actually completed. Draining it
--     before the replay produces the exact 333/444 regression.
---------------------------------------------------------------------------
runScheduled()
env.QUI_ApplyAllFrameAnchors() -- immediate pass; arms the one-frame throttle
posChild.width = 77
sizeChild.width = 88
inCombat = true
env.QUI_ReanchorFramePositionOnly("qtestPosChild")
sizeChild.protectedAnswer = true
env.QUI_ApplyFrameAnchor("qtestSizeChild") -- latches the regen full apply
sizeChild.protectedAnswer = false
local realSizeChildSetWidth = sizeChild.SetWidth
local nestedReplayRequested = false
sizeChild.SetWidth = function(self, width)
    realSizeChildSetWidth(self, width)
    if not nestedReplayRequested then
        nestedReplayRequested = true
        env.QUI_ApplyAllFrameAnchors()
    end
end
posOnlyCalls = 0
fireRegen()
runScheduled() -- run the pass coalesced from inside the first replay
sizeChild.SetWidth = realSizeChildSetWidth
check("throttled-regen: replay eventually drains the position-only op",
    posOnlyCalls >= 1, ("%d position-only calls"):format(posOnlyCalls))
check("throttled-regen: nested coalescing path was exercised",
    nestedReplayRequested, "size callback did not request a replay")
check("throttled-regen: coalesced full apply preserves position-only size",
    posChild.width == 77, ("width %s"):format(tostring(posChild.width)))
check("throttled-regen: coalesced full apply still sizes unrelated keys",
    sizeChild.width == 444, ("width %s"):format(tostring(sizeChild.width)))

---------------------------------------------------------------------------
-- (v) THROWING full apply: suppression is dynamic pass state, so a resolver
--     exception must not leave positionOnly origins permanently exempt from
--     later ordinary auto-sizing.
---------------------------------------------------------------------------
runScheduled()
posParent.shownAnswer = SECRET
env.QUI_ReanchorFramePositionOnly("qtestPosChild") -- supplies suppression set
posParent.shownAnswer = true
local throwChild = StubFrame("throwChild")
local throwResolver = false
env.QUI_RegisterFrameResolver("qtestThrowChild", {
    resolver = function()
        if throwResolver then error("qtest resolver failure") end
        return throwChild
    end,
})
frameAnchoring.qtestThrowChild = {
    parent = "screen", point = "CENTER", relative = "CENTER",
    offsetX = 0, offsetY = 0,
}
throwResolver = true
local throwApplyOK = pcall(env.QUI_ApplyAllFrameAnchors, true)
check("throw-cleanup: resolver exception escapes the failed full apply",
    not throwApplyOK, "full apply unexpectedly succeeded")
throwResolver = false
posChild.width = 77
env.QUI_ApplyFrameAnchor("qtestPosChild")
check("throw-cleanup: later ordinary apply is not suppression-latched",
    posChild.width == 333, ("width %s"):format(tostring(posChild.width)))
frameAnchoring.qtestThrowChild = nil
runScheduled()

---------------------------------------------------------------------------
-- (w) NESTED force=true full apply: a SetWidth side effect can synchronously
--     enter a forced pass while the regen pass still owns positionOnly size
--     suppression. The nested pass must inherit that suppression, restore the
--     outer pass's state, and leave the after-apply drain for the OUTERMOST
--     pass (exact unfixed repro: width 77 -> 222).
---------------------------------------------------------------------------
local nestedParent = StubFrame("nestedParent")
local nestedTrigger = StubFrame("nestedTrigger")
nestedParent.width = 222
env.QUI_RegisterFrameResolver("qtestNestedParent",
    { resolver = function() return nestedParent end })
env.QUI_RegisterFrameResolver("qtestNestedTrigger",
    { resolver = function() return nestedTrigger end })
frameAnchoring.qtestNestedTrigger = {
    parent = "qtestNestedParent", point = "TOP", relative = "BOTTOM",
    offsetX = 0, offsetY = 0, autoWidth = true,
}
local oldPosParentKey = frameAnchoring.qtestPosChild.parent
frameAnchoring.qtestPosChild.parent = "qtestNestedTrigger"
local realNestedTriggerSetWidth = nestedTrigger.SetWidth
local nestedForceRequested = false
local nestedDrainedInsideForce = false
nestedTrigger.SetWidth = function(self, width)
    realNestedTriggerSetWidth(self, width)
    if not nestedForceRequested then
        nestedForceRequested = true
        env.QUI_ApplyAllFrameAnchors(true)
        nestedDrainedInsideForce = posOnlyCalls > 0
    end
end

posChild.width = 77
posOnlyCalls = 0
inCombat = true
env.QUI_ReanchorFramePositionOnly("qtestPosChild")
nestedTrigger.protectedAnswer = true
env.QUI_ApplyFrameAnchor("qtestNestedTrigger") -- latches the regen full apply
nestedTrigger.protectedAnswer = false
posOnlyCalls = 0
fireRegen()
check("nested-force: forced full apply was entered",
    nestedForceRequested, "SetWidth did not enter the forced pass")
check("nested-force: consumer drain waits for the outermost pass",
    not nestedDrainedInsideForce, "position-only op drained inside nested force")
check("nested-force: outer suppression survives the nested pass",
    posChild.width == 77, ("width %s"):format(tostring(posChild.width)))
check("nested-force: outer completion eventually drains the consumer",
    posOnlyCalls >= 1, ("%d position-only calls"):format(posOnlyCalls))

nestedTrigger.SetWidth = realNestedTriggerSetWidth
frameAnchoring.qtestPosChild.parent = oldPosParentKey
frameAnchoring.qtestNestedTrigger = nil
runScheduled()

---------------------------------------------------------------------------
-- (x) THROWING regen full apply: the exception is contained and the REQUIRED
--     full reconcile remains latched. Consumer callbacks/ops stay queued until
--     a successful retry, which preserves width 77 while an ordered downstream
--     auto-width key eventually advances from 88 -> 555.
---------------------------------------------------------------------------
local throwAfterChild = StubFrame("throwAfterChild")
throwChild.width = 555
throwAfterChild.width = 88
env.QUI_RegisterFrameResolver("qtestThrowAfterChild",
    { resolver = function() return throwAfterChild end })
frameAnchoring.qtestThrowChild = {
    parent = "screen", point = "CENTER", relative = "CENTER",
    offsetX = 0, offsetY = 0,
}
frameAnchoring.qtestThrowAfterChild = {
    parent = "qtestThrowChild", point = "TOP", relative = "BOTTOM",
    offsetX = 0, offsetY = 0, autoWidth = true,
}

posChild.width = 77
posOnlyCalls = 0
inCombat = true
env.QUI_ReanchorFramePositionOnly("qtestPosChild")
sizeChild.protectedAnswer = true
env.QUI_ApplyFrameAnchor("qtestSizeChild") -- latches the required full apply
sizeChild.protectedAnswer = false
posOnlyCalls = 0
throwResolver = true
local regenThrowOK, regenThrowError = pcall(fireRegen)
check("regen-throw: failed full apply is contained",
    regenThrowOK, tostring(regenThrowError))
check("regen-throw: failed pass does not drain the consumer early",
    posOnlyCalls == 0, ("%d position-only calls"):format(posOnlyCalls))
check("regen-throw: downstream key remains unapplied after failure",
    throwAfterChild.width == 88,
    ("width %s"):format(tostring(throwAfterChild.width)))

throwResolver = false
fireRegen()
check("regen-throw: successful retry drains the preserved consumer",
    posOnlyCalls >= 1, ("%d position-only calls"):format(posOnlyCalls))
check("regen-throw: successful retry preserves position-only size",
    posChild.width == 77, ("width %s"):format(tostring(posChild.width)))
check("regen-throw: successful retry completes downstream full apply",
    throwAfterChild.width == 555,
    ("width %s"):format(tostring(throwAfterChild.width)))

frameAnchoring.qtestThrowAfterChild = nil
frameAnchoring.qtestThrowChild = nil
runScheduled()

---------------------------------------------------------------------------
-- (y) DEFERRED regen replay becomes SKIPPED: layout mode can activate after
--     the regen timer coalesces onto the throttle but before its OnUpdate.
--     The independently replayable consumer must drain exactly once on that
--     skipped replay, not remain queued for a surprising later bulk apply.
---------------------------------------------------------------------------
local oldLayoutModeProbe = env.QUI_IsLayoutModeActive
local layoutModeActive = false
env.QUI_IsLayoutModeActive = function() return layoutModeActive end

env.QUI_ApplyAllFrameAnchors() -- immediate pass arms the throttle
posChild.width = 77
inCombat = true
env.QUI_ReanchorFramePositionOnly("qtestPosChild")
sizeChild.protectedAnswer = true
env.QUI_ApplyFrameAnchor("qtestSizeChild") -- latches the regen full apply
sizeChild.protectedAnswer = false
posOnlyCalls = 0
inCombat = false
regenFrame.scripts.OnEvent(regenFrame, "PLAYER_REGEN_ENABLED")
local deferredRegenTimer = assert(table.remove(scheduled),
    "deferred regen timer missing")
deferredRegenTimer() -- queues after-apply drain; throttle replay not run yet
check("skipped-replay: consumer remains queued before OnUpdate",
    posOnlyCalls == 0, ("%d position-only calls"):format(posOnlyCalls))

layoutModeActive = true
for _, f in ipairs(createdFrames) do
    if f.scripts.OnUpdate then f.scripts.OnUpdate(f) end
end
check("skipped-replay: layout-mode skip drains the consumer once",
    posOnlyCalls == 1, ("%d position-only calls"):format(posOnlyCalls))
check("skipped-replay: position-only drain preserves module size",
    posChild.width == 77, ("width %s"):format(tostring(posChild.width)))

layoutModeActive = false
local callsAfterSkippedReplay = posOnlyCalls
runScheduled()
env.QUI_ApplyAllFrameAnchors()
runScheduled()
check("skipped-replay: later bulk apply has no surprise consumer drain",
    posOnlyCalls == callsAfterSkippedReplay,
    ("%d -> %d position-only calls"):format(callsAfterSkippedReplay, posOnlyCalls))
env.QUI_IsLayoutModeActive = oldLayoutModeProbe

env.QUI_ReanchorFramePositionOnly = realPosOnly
frameAnchoring.qtestPosChild.autoWidth = nil

---------------------------------------------------------------------------
-- (u) Source pins: InstallVisibilityHook guard lookups are protected.
--     The resolved target can be a forbidden frame / 68675 DenyTaintedAccess
--     child where the member LOOKUP itself throws (round-18b guard-position
--     class). Section (v) below models this behaviorally with SELECTIVE
--     throwing __index proxies; the source pins remain for the probe-order
--     shape a proxy cannot model — Lua 5.1 __eq never fires against nil, so
--     a throwing `frame == nil` truth-test on a secret is unstubable.
---------------------------------------------------------------------------
local srcF = assert(io.open("modules/layout/anchoring.lua", "rb"))
local anchSrc = srcF:read("*a"); srcF:close()
anchSrc = anchSrc:gsub("\r\n", "\n")
check("pin: visibility-hook existence lookups run inside pcall",
    anchSrc:find("pcall(ProbeVisibilityHookMembers, frame)", 1, true) ~= nil)
check("pin: no raw guard lookup of frame.HookScript remains",
    anchSrc:find("not frame or not frame.HookScript", 1, true) == nil)
check("pin: GetAlpha is not pre-indexed outside its pcall",
    anchSrc:find("pcall(frame.GetAlpha", 1, true) == nil
    and anchSrc:find("pcall(InvokeGetAlpha, frame)", 1, true) ~= nil)
check("pin: secret probe precedes the nil check on the hook target",
    (function()
        local probePos = anchSrc:find("nsHelpers.IsSecretValue(frame))", 1, true)
        local nilPos = anchSrc:find("or frame == nil then", 1, true)
        return probePos ~= nil and nilPos ~= nil and probePos < nilPos
    end)())

---------------------------------------------------------------------------
-- (v) BEHAVIORAL: selective throwing __index proxies through the FULL apply.
--     The anchor parent delegates every member to a plain stub EXCEPT the
--     members under test, whose LOOKUP throws (round-18b guard-position
--     class: forbidden frame / DenyTaintedAccess child). The apply must
--     contain the throw, still position the child, and never take a
--     hide/show decision from an unreadable parent.
--       HookScript lookup throws  -> member probe fails, no hook installed
--       SetAlpha lookup throws    -> probe fails closed, no hook at all
--       GetAlpha lookup throws    -> probe passed, hooks install; the alpha
--                                    read is contained (pcall'd InvokeGetAlpha
--                                    + FrameVisibleSecure lookup probe)
---------------------------------------------------------------------------
local function ThrowingMemberProxy(base, throwMembers)
    return setmetatable({}, {
        __index = function(_, k)
            if throwMembers[k] then
                error("Attempted to access forbidden member " .. tostring(k))
            end
            return base[k]
        end,
        __newindex = function(_, k, v) base[k] = v end,
    })
end

inCombat = false
-- Normalize first: a readable-VISIBLE parent legitimately restores (Show)
-- a child whose hidden latch is still set from earlier sections. Clear the
-- latch on the plain parent so any Show/Hide inside the proxy cases can
-- only come from a decision taken against the throwing parent itself.
activeParent = parentFrame
parentFrame.shownAnswer = true
parentFrame.alphaAnswer = 1
env.QUI_ApplyFrameAnchor("qtestHideChild")
runScheduled()

local proxyCases = {
    { label = "HookScript lookup throws", throws = { HookScript = true },
      expectHooks = false },
    { label = "SetAlpha lookup throws", throws = { SetAlpha = true },
      expectHooks = false },
    { label = "GetAlpha lookup throws", throws = { GetAlpha = true },
      expectHooks = true },
}
for _, case in ipairs(proxyCases) do
    local base = StubFrame("proxyParent", true)
    activeParent = ThrowingMemberProxy(base, case.throws)
    resetGeom()
    local okProxy, errProxy = pcall(env.QUI_ApplyFrameAnchor, "qtestHideChild")
    runScheduled() -- unreadable-visibility retry replays must stay contained too
    check(("proxy %s: apply does not error"):format(case.label),
        okProxy, tostring(errProxy))
    check(("proxy %s: child still positioned"):format(case.label),
        sawGeom("hideChild:SetPoint"), geomSummary())
    check(("proxy %s: no hide/show decision from throwing parent"):format(case.label),
        not sawGeom("hideChild:Hide") and not sawGeom("hideChild:Show"),
        geomSummary())
    if case.expectHooks then
        check(("proxy %s: OnShow/OnHide visibility hooks installed"):format(case.label),
            base.hookScripts.OnShow ~= nil and base.hookScripts.OnHide ~= nil)
    else
        check(("proxy %s: NO hook installed after failed member probe"):format(case.label),
            next(base.hookScripts) == nil)
    end
end
-- Restore the plain parent so the swap never leaks past this section.
activeParent = parentFrame
parentFrame.shownAnswer = true
parentFrame.alphaAnswer = 1
env.QUI_ApplyFrameAnchor("qtestHideChild")
runScheduled()

---------------------------------------------------------------------------
-- (z) SetAlpha visibility-hook latch: an UNREADABLE initial alpha must be
--     preserved as UNKNOWN (nil), never collapsed to "visible". Unfixed
--     repro: the hook installs while GetAlpha answers secret (HUD fade),
--     latching wasAlphaHidden=false; the parent is actually faded out and
--     a later readable pass hides the child; the one-shot unreadable retry
--     is burned. When the parent fades back in, SetAlpha(1) compares
--     false==false — no transition seen, no re-anchor, the child stays
--     hidden forever. Fixed: unknown stays nil, so the FIRST readable
--     alpha callback fires the re-anchor exactly once, then normal edge
--     detection latches. This section invokes the INSTALLED callback (the
--     env-wide hooksecurefunc stub is a no-op, so the other sections never
--     exercise it).
---------------------------------------------------------------------------
do
    inCombat = false
    local capturedHooks = {}
    local realHooksecurefunc = env.hooksecurefunc
    env.hooksecurefunc = function(frame, method, cb)
        capturedHooks[frame] = capturedHooks[frame] or {}
        capturedHooks[frame][method] = cb
    end

    local alphaParent = StubFrame("alphaParent")
    local alphaChild = StubFrame("alphaChild")
    env.QUI_RegisterFrameResolver("qtestAlphaParent",
        { resolver = function() return alphaParent end })
    env.QUI_RegisterFrameResolver("qtestAlphaChild",
        { resolver = function() return alphaChild end })
    frameAnchoring.qtestAlphaChild = {
        parent = "qtestAlphaParent", point = "TOP", relative = "BOTTOM",
        offsetX = 0, offsetY = -4, hideWithParent = true,
    }

    -- Hook installs while the alpha answer is SECRET: initial state UNKNOWN.
    alphaParent.shownAnswer = true
    alphaParent.alphaAnswer = SECRET
    env.QUI_ApplyFrameAnchor("qtestAlphaChild")
    runScheduled() -- burn the one-shot unreadable retry (answer still secret)
    local alphaCb = capturedHooks[alphaParent] and capturedHooks[alphaParent].SetAlpha
    check("alpha-latch: SetAlpha hook installed under a secret initial alpha",
        alphaCb ~= nil, "no SetAlpha callback captured")

    -- The parent turns out to be faded OUT (readable pass hides the child)...
    alphaParent.alphaAnswer = 0
    resetGeom()
    env.QUI_ApplyFrameAnchor("qtestAlphaChild")
    runScheduled()
    check("alpha-latch: readable alpha~0 pass hides the child",
        sawGeom("alphaChild:Hide"), geomSummary())
    check("alpha-latch: hidden latch set",
        env.QUI_IsFrameHiddenByAnchor("qtestAlphaChild") == true)

    -- ...then fades back in via SetAlpha(1). The callback's stored state is
    -- UNKNOWN, so this first readable transition MUST re-run the anchor
    -- pass (unfixed: false==false, no re-run, child parked hidden forever).
    alphaParent.alphaAnswer = 1
    resetGeom()
    alphaCb(alphaParent, 1)
    runScheduled()
    check("alpha-latch: first readable SetAlpha re-runs the anchor pass",
        sawGeom("alphaChild:Show"), geomSummary())
    check("alpha-latch: hidden latch cleared",
        env.QUI_IsFrameHiddenByAnchor("qtestAlphaChild") == false)

    -- The unknown fired once and latched: an identical readable alpha is a
    -- NO-transition and must not re-enter the bulk pass at all. Counted at
    -- the METHOD (called synchronously by the hook before any throttling),
    -- and asserted BEFORE runScheduled so throttle replays never pollute.
    local visApplies = 0
    local realBulk = Anchoring.ApplyAllFrameAnchors
    Anchoring.ApplyAllFrameAnchors = function(self, ...)
        visApplies = visApplies + 1
        return realBulk(self, ...)
    end
    alphaCb(alphaParent, 1)
    check("alpha-latch: repeated readable alpha is edge-detected (no re-fire)",
        visApplies == 0, ("%d applies"):format(visApplies))

    -- Normal edge detection continues: visible -> hidden fires...
    alphaParent.alphaAnswer = 0
    alphaCb(alphaParent, 0)
    check("alpha-latch: visible->hidden edge fires the anchor pass",
        visApplies == 1, ("%d applies"):format(visApplies))
    runScheduled()
    check("alpha-latch: edge pass re-hides the child",
        env.QUI_IsFrameHiddenByAnchor("qtestAlphaChild") == true)

    -- ...and a SECRET alpha through the hook is ignored: no fire, no latch
    -- corruption (the HUD curve passes secret HP-derived alphas through
    -- SetAlpha intentionally).
    local appliesBefore = visApplies
    alphaCb(alphaParent, SECRET)
    check("alpha-latch: secret alpha through the hook is ignored",
        visApplies == appliesBefore, ("%d applies"):format(visApplies))
    alphaParent.alphaAnswer = 1
    alphaCb(alphaParent, 1)
    check("alpha-latch: hidden->visible edge still fires after the secret call",
        visApplies == appliesBefore + 1, ("%d applies"):format(visApplies))
    runScheduled()
    check("alpha-latch: child restored after the secret interlude",
        env.QUI_IsFrameHiddenByAnchor("qtestAlphaChild") == false)

    Anchoring.ApplyAllFrameAnchors = realBulk
    env.hooksecurefunc = realHooksecurefunc
    frameAnchoring.qtestAlphaChild = nil
    runScheduled()
end

print(("\n%d failure(s)"):format(failures))
if failures == 0 then
    print("OK: anchoring_apply_frame_anchor_secret_gate_test")
end
os.exit(failures == 0 and 0 or 1)
