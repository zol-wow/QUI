-- tests/unit/actionbars_extra_zone_central_anchor_integration_test.lua
-- Run: lua tests/unit/actionbars_extra_zone_central_anchor_integration_test.lua
--
-- INTEGRATION harness: loads the REAL central anchoring implementation
-- (modules/layout/anchoring.lua) together with the REAL extra/zone chunk
-- (QUI_ActionBars/actionbars/actionbars_extra_buttons.lua) and the REAL
-- shared helpers (core/utils.lua), then drives ApplyExtraButtonFrameAnchor
-- end to end THROUGH _G.QUI_ApplyFrameAnchor — no stubbed anchor API.
-- Companion to actionbars_extra_button_combat_gate_test.lua (which stubs the
-- central apply to isolate the chunk) and
-- anchoring_apply_frame_anchor_secret_gate_test.lua (which drives the central
-- apply directly). This file proves the two systems agree at the seam:
--
--   (a) OUT OF COMBAT both saved anchors position the REAL holders through
--       the central path with the saved point/offsets (screen -> UIParent).
--   (b) IN COMBAT the extra path defers BEFORE the central apply runs — no
--       geometry reaches the extra holder even though the holder itself
--       probes unrestricted — and marks the regen reconcile pending.
--   (c) IN COMBAT the zone anchor applies LIVE through the central path when
--       the holder probes unrestricted (mid-fight grants keep tracking the
--       mover).
--   (d) IN COMBAT a true / SECRET / THROWING protection answer on the zone
--       holder makes the CENTRAL path defer (fail-closed probe before any
--       truth-test); the real PLAYER_REGEN_ENABLED reconcile repositions the
--       holder once the answer is readable.

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

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

---------------------------------------------------------------------------
-- Shared world state: one combat flag, one timer queue, one UIParent.
---------------------------------------------------------------------------
local inCombat = false
local scheduled = {}

local geomCalls = {}
local function record(name) geomCalls[#geomCalls + 1] = name end
local function geomSummary()
    return #geomCalls == 0 and "(none)" or table.concat(geomCalls, ", ")
end
local function sawGeom(needle)
    for _, name in ipairs(geomCalls) do
        if name == needle then return true end
    end
    return false
end
local function resetGeom()
    for i = #geomCalls, 1, -1 do geomCalls[i] = nil end
end

-- Full-API frame stub the central anchoring path can resolve, probe, and
-- reposition. silent=true skips the geometry recorder (internal frames the
-- anchoring chunk CreateFrames itself).
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
    function f:HookScript(which, fn) self.hookScripts[which] = fn end
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
    function f:GetWidth() return 100 end
    function f:GetHeight() return 100 end
    function f:GetEffectiveScale() return 1 end
    function f:GetScale() return 1 end
    function f:SetSize() end
    return f
end

local UIParentStub = StubFrame("UIParent", true)

---------------------------------------------------------------------------
-- REAL central anchoring chunk in a stub WoW environment.
---------------------------------------------------------------------------
local frameAnchoring = {}
ns.Addon = { db = { profile = { frameAnchoring = frameAnchoring } } }

local createdFrames = {}
local anchorEnv = setmetatable({
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
anchorEnv._G = anchorEnv
anchorEnv.UIParent = UIParentStub

local ANCHORING = "modules/layout/anchoring.lua"
local anchorChunk = assert(loadstring(readFile(ANCHORING), "@" .. ANCHORING))
setfenv(anchorChunk, anchorEnv)
anchorChunk("QUI", ns)

assert(type(anchorEnv.QUI_ApplyFrameAnchor) == "function",
    "anchoring chunk must export _G.QUI_ApplyFrameAnchor")
assert(type(anchorEnv.QUI_HasFrameAnchor) == "function",
    "anchoring chunk must export _G.QUI_HasFrameAnchor")
assert(type(anchorEnv.QUI_RegisterFrameResolver) == "function",
    "anchoring chunk must export _G.QUI_RegisterFrameResolver")

local function runScheduled()
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
runScheduled() -- load-time timers

-- The real PLAYER_REGEN_ENABLED reconcile frame from the anchoring chunk.
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

---------------------------------------------------------------------------
-- REAL extra/zone chunk wired to the REAL central anchor API: the chunk's
-- _G *is* the anchoring environment, so _G.QUI_HasFrameAnchor and
-- _G.QUI_ApplyFrameAnchor resolve to the genuine exports above.
---------------------------------------------------------------------------
assert(loadfile("QUI_ActionBars/actionbars/actionbars_env.lua"))("QUI", ns)
local abEnv = ns.ActionBarsEnv

abEnv._G = anchorEnv
abEnv.UIParent = UIParentStub
abEnv.InCombatLockdown = function() return inCombat end
abEnv.issecretvalue = fakeIsSecretValue
abEnv.hooksecurefunc = function() end
abEnv.C_Timer = { After = function(_, fn) scheduled[#scheduled + 1] = fn end }
abEnv.ActionBarsOwned = {}
abEnv.Helpers = ns.Helpers
abEnv.ExtraActionBarFrame = StubFrame("ExtraActionBarFrame", true)
abEnv.ZoneAbilityFrame = StubFrame("ZoneAbilityFrame", true)
abEnv.ExtraAbilityContainer = nil -- container acquisition is out of scope here

local extraSettings = { enabled = true, scale = 1.0 }
local zoneSettings = { enabled = true, scale = 1.0 }
abEnv.GetCore = function()
    return {
        db = { profile = {
            actionBars = { bars = {
                extraActionButton = extraSettings,
                zoneAbility       = zoneSettings,
            } },
            frameAnchoring = frameAnchoring,
        } },
    }
end

local CHUNK = "QUI_ActionBars/actionbars/actionbars_extra_buttons.lua"
assert(loadfile(CHUNK))("QUI", ns)

local extraHolder = StubFrame("extraHolder")
local zoneHolder = StubFrame("zoneHolder")
abEnv.extraBtnState.extraActionHolder = extraHolder
abEnv.extraBtnState.zoneAbilityHolder = zoneHolder

local ApplyExtraButtonFrameAnchor = assert(abEnv.ApplyExtraButtonFrameAnchor,
    "chunk must declare ApplyExtraButtonFrameAnchor")

-- The REAL central resolvers for the two mover keys: exactly what the live
-- addon registers for the extra/zone holders.
anchorEnv.QUI_RegisterFrameResolver("extraActionButton",
    { resolver = function() return extraHolder end })
anchorEnv.QUI_RegisterFrameResolver("zoneAbility",
    { resolver = function() return zoneHolder end })

-- Saved anchor overrides in the exact shape SaveExtraButtonFrameAnchor
-- writes (screen-parented, keepInPlace).
frameAnchoring.extraActionButton = {
    parent = "screen", point = "CENTER", relative = "CENTER",
    offsetX = -120, offsetY = -25,
    sizeStable = true, autoWidth = false, autoHeight = false,
    hideWithParent = false, keepInPlace = true,
    widthAdjust = 0, heightAdjust = 0,
}
frameAnchoring.zoneAbility = {
    parent = "screen", point = "TOPLEFT", relative = "TOPLEFT",
    offsetX = 150, offsetY = -27,
    sizeStable = true, autoWidth = false, autoHeight = false,
    hideWithParent = false, keepInPlace = true,
    widthAdjust = 0, heightAdjust = 0,
}

check("real QUI_HasFrameAnchor sees both saved overrides",
    anchorEnv.QUI_HasFrameAnchor("extraActionButton") == true
        and anchorEnv.QUI_HasFrameAnchor("zoneAbility") == true)

---------------------------------------------------------------------------
-- (a) OUT OF COMBAT: both anchors land on the holders through the REAL
--     central path with the saved geometry.
---------------------------------------------------------------------------
inCombat = false

resetGeom()
extraHolder.points = {}
ApplyExtraButtonFrameAnchor("extraActionButton")
runScheduled()
check("OOC extra: central apply repositions the holder",
    sawGeom("extraHolder:SetPoint"), geomSummary())
local pt, rel, relPt, x, y = extraHolder:GetPoint(1)
check("OOC extra: saved point/offsets applied against UIParent",
    pt == "CENTER" and rel == UIParentStub and relPt == "CENTER"
        and x == -120 and y == -25,
    ("got (%s, %s, %s, %s, %s)"):format(tostring(pt),
        tostring(rel and rel.__name), tostring(relPt), tostring(x), tostring(y)))

resetGeom()
zoneHolder.points = {}
ApplyExtraButtonFrameAnchor("zoneAbility")
runScheduled()
check("OOC zone: central apply repositions the holder",
    sawGeom("zoneHolder:SetPoint"), geomSummary())
-- Size-stable anchoring (the on-disk default) normalizes every apply to
-- CENTER with recomputed offsets (ComputeCenterOffsetsForAnchor). Holder
-- and UIParent stubs share a 100x100 rect, so the TOPLEFT->TOPLEFT source/
-- target corrections cancel and the saved offsets pass through verbatim.
pt, rel, relPt, x, y = zoneHolder:GetPoint(1)
check("OOC zone: size-stable normalized geometry against UIParent",
    pt == "CENTER" and rel == UIParentStub and relPt == "CENTER"
        and x == 150 and y == -27,
    ("got (%s, %s, %s, %s, %s)"):format(tostring(pt),
        tostring(rel and rel.__name), tostring(relPt), tostring(x), tostring(y)))

---------------------------------------------------------------------------
-- (b) IN COMBAT the extra path defers BEFORE the central apply: no geometry
--     reaches the holder even though the holder probes unrestricted.
---------------------------------------------------------------------------
inCombat = true

resetGeom()
extraHolder.points = {}
abEnv.ActionBarsOwned.pendingExtraButtonRefresh = false
ApplyExtraButtonFrameAnchor("extraActionButton")
runScheduled()
check("in-combat extra: no geometry reaches the holder",
    #geomCalls == 0, geomSummary())
check("in-combat extra: marks the pending regen refresh",
    abEnv.ActionBarsOwned.pendingExtraButtonRefresh == true)

---------------------------------------------------------------------------
-- (c) IN COMBAT the zone anchor applies LIVE through the central path when
--     the holder probes unrestricted.
---------------------------------------------------------------------------
resetGeom()
zoneHolder.points = {}
ApplyExtraButtonFrameAnchor("zoneAbility")
runScheduled()
check("in-combat zone: central apply repositions the unrestricted holder",
    sawGeom("zoneHolder:SetPoint"), geomSummary())
pt, rel, relPt, x, y = zoneHolder:GetPoint(1)
check("in-combat zone: geometry still matches the saved anchor",
    pt == "CENTER" and rel == UIParentStub and x == 150 and y == -27,
    ("got (%s, %s, %s, %s)"):format(tostring(pt),
        tostring(rel and rel.__name), tostring(x), tostring(y)))

---------------------------------------------------------------------------
-- (d) IN COMBAT a restricted / SECRET / THROWING holder answer defers the
--     CENTRAL apply; the real regen reconcile lands it once readable.
---------------------------------------------------------------------------
local gateCases = {
    { label = "IsProtected=true", field = "protectedAnswer", value = true },
    { label = "IsProtected=SECRET", field = "protectedAnswer", value = SECRET },
    { label = "IsProtected throws", field = "protectedAnswer",
      value = function() error("secure-context probe") end },
    { label = "IsAnchoringRestricted=SECRET", field = "restrictedAnswer", value = SECRET },
}
for _, case in ipairs(gateCases) do
    inCombat = true
    zoneHolder.protectedAnswer = false
    zoneHolder.restrictedAnswer = false
    zoneHolder[case.field] = case.value
    resetGeom()
    zoneHolder.points = {}
    local ok, err = pcall(ApplyExtraButtonFrameAnchor, "zoneAbility")
    check(("in-combat zone %s: apply does not error"):format(case.label),
        ok, tostring(err))
    check(("in-combat zone %s: no geometry reaches the holder"):format(case.label),
        #geomCalls == 0, geomSummary())

    -- Readable again: the real PLAYER_REGEN_ENABLED reconcile repositions.
    zoneHolder[case.field] = false
    resetGeom()
    fireRegen()
    check(("post-combat reconcile after %s repositions the holder"):format(case.label),
        sawGeom("zoneHolder:SetPoint"), geomSummary())
end
zoneHolder.protectedAnswer = false
zoneHolder.restrictedAnswer = false
inCombat = false

print(("\n%d failure(s)"):format(failures))
if failures == 0 then
    print("OK: actionbars_extra_zone_central_anchor_integration_test")
end
os.exit(failures == 0 and 0 or 1)
