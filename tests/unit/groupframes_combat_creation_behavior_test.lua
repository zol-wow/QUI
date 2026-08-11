-- tests/unit/groupframes_combat_creation_behavior_test.lua
-- PTR7 68914 combat-creation contract (replaces the retired
-- groupframes_prealloc_headroom_behavior_test: prealloc/headroom existed only
-- because creation used to be combat-forbidden — crashed earlier 12.1
-- clients — and both were removed once Drew proved container creation,
-- AddAuraGroup and AddAuraSlot combat-legal in-game on 2026-07-24).
--
-- groupframes_auras.lua needs real WoW frames and cannot run headless, so
-- this file loads the real core glue it calls through (core/aura_glue.lua's
-- AuraGlue.RunConfigPass -> core/aura_skin.lua's AuraSkin.Configure) against
-- a fake container that SPIES on AddAuraGroup, and proves the contract the
-- retirement rests on:
--
--   (a) an OOC RunConfigPass(..., allowCreate=true) registers the group
--       (baseline, unchanged behavior).
--   (b) a combat pass on an ALREADY-REGISTERED container reuses the key —
--       no second AddAuraGroup, live mutators still reconcile.
--   (c) THE PTR7 CHANGE: a FRESH container in COMBAT with allowCreate=true
--       DOES register its group — AddAuraGroup is no longer combat-gated
--       inside Configure. This is the mid-combat joiner path that used to
--       need prealloc/headroom spares.
--   (d) RunConfigPass's allowCreate=false arm is only the SafeCall-GUARDED
--       Configure variant (surprise-restriction belt with a Restyle
--       fallback) — with Configure's combat gate gone, registration happens
--       on BOTH arms; nothing inside core gates creation anymore. Container
--       CreateFrame remains allowCreate-gated in the consuming passes
--       (groupframes/unitframe ApplyElementPass), which is where the
--       caller policy lives.
--
-- Run: lua tests/unit/groupframes_combat_creation_behavior_test.lua

local fails = 0
local function check(name, ok, detail)
    if ok then print("  ok  " .. name)
    else fails = fails + 1; print("FAIL  " .. name .. (detail and ("  " .. detail) or "")) end
end

----------------------------------------------------------------------------
-- Combat-state toggle: RunConfigPass/Configure both read InCombatLockdown()
-- live, so a single mutable upvalue drives the OOC and combat phases.
----------------------------------------------------------------------------
local inCombat = false
_G.InCombatLockdown = function() return inCombat end
_G.AuraContainerSortMethod = { Default = 1 }
_G.AuraContainerSortDirection = { Normal = 1 }
_G.AnchorUtil = { FlowDirection = { Left = -1, Right = 1, Up = 1, Down = -1 }, FlowLayoutAxis = { Horizontal = 0, Vertical = 1 } }
-- styleButton's linear branch (phase (e)) wires SetDurationBar with these.
_G.Enum = {
    StatusBarTimerDirection = { RemainingTime = 1, ElapsedTime = 2 },
    StatusBarInterpolation = { Immediate = 1, Linear = 2 },
}

local function Stub()
    local t = {}
    function t:SetAllPoints() end
    function t:SetPoint() end
    function t:ClearAllPoints() end
    function t:SetColorTexture() end
    function t:SetTexCoord() end
    function t:DisablePixelSnap() end
    function t:SetTextColor() end
    function t:SetAlpha() end
    function t:SetFont() end
    function t:SetHideCountdownNumbers() end
    function t:SetDrawSwipe() end
    function t:SetReverse() end
    function t:SetText() end
    function t:SetStatusBarTexture() end
    function t:SetOrientation() end
    function t:SetStatusBarColor() end
    function t:Show() end
    function t:Hide() end
    function t:CreateTexture() return Stub() end
    function t:CreateFontString() return Stub() end
    return t
end
_G.CreateFrame = function() return Stub() end

local function MakeButton()
    local b = Stub()
    function b:SetCancelAuraButtons() end
    function b:SetSize() end
    function b:SetIcon() end
    function b:AddDispelTypeTexture() end
    function b:ClearDispelTypeTextures() end
    function b:SetDispelTypeText() end
    function b:SetDurationCooldown() end
    function b:SetDurationText() end
    function b:SetApplicationCount() end
    -- Records the linear-fill wiring for phase (e): the engine mixin method
    -- styleButton feature-detects before wiring the birth-created StatusBar.
    function b:SetDurationBar(bar, _opts)
        b._durationBarCalls = (b._durationBarCalls or 0) + 1
        b._durationBar = bar
    end
    return b
end

-- Fake CustomAuraContainer with an AddAuraGroup SPY: records every call so
-- the test can assert an EXACT count across the OOC and combat phases.
local function MakeContainer()
    local c = { _addAuraGroupCalls = 0, _mutatorCalls = 0, _registeredKeys = {}, _maxFrameCounts = {} }
    function c:HasAuraGroup(key) return self._registeredKeys[key] == true end
    function c:AddAuraGroup(key, filter, opts)
        c._addAuraGroupCalls = c._addAuraGroupCalls + 1
        c._registeredKeys[key] = true
        c._maxFrameCounts[key] = opts.maxFrameCount
        c._lastInitFn = opts.initializeFrame
        c._capturedButton = MakeButton()
        c._lastInitFn(c._capturedButton)
    end
    function c:SetAuraGroupMaxFrameCount(key, count)
        self._mutatorCalls = self._mutatorCalls + 1
        self._maxFrameCounts[key] = count
    end
    function c:SetAuraGroupSortMethod() self._mutatorCalls = self._mutatorCalls + 1 end
    function c:SetAuraGroupCandidateFilters() self._mutatorCalls = self._mutatorCalls + 1 end
    function c:SetAuraGroupLayout() self._mutatorCalls = self._mutatorCalls + 1 end
    function c:SetFlowLayoutAnchorPoint() end
    function c:SetFlowLayoutGrowthDirection() end
    function c:SetFlowLayoutPadding() end
    function c:SetFlowLayoutAxis() end
    function c:SetFlowLayoutMaximumLineSize() end
    -- Mirrors the real AuraContainerSharedMixin:SetUnit contract (asserts a
    -- STRING unit token, no nil tolerance).
    function c:SetUnit(unitToken)
        assert(type(unitToken) == "string", "SetUnit requires a string unit token")
        self.unitToken = unitToken
    end
    function c:SetEnabled(v) self.enabled = v end
    function c:Show() self.shown = true end
    function c:Hide() self.shown = false end
    return c
end

local ns = {
    SafeCall = function(_policy, fn, ...) return pcall(fn, ...) end,
    SafeCallMethod = function(_policy, obj, name, ...) return pcall(function(...) return obj[name](obj, ...) end, ...) end,
    SafeCallMethodIfPresent = function(_policy, obj, name, ...) if obj == nil then return nil end local okP, m = pcall(function() return obj[name] end) if not okP then return false end if m == nil then return nil end return pcall(m, obj, ...) end,
}
assert(loadfile("core/aura_theme.lua"))("QUI", ns)
assert(loadfile("core/aura_skin.lua"))("QUI", ns)
assert(loadfile("core/aura_elements.lua"))("QUI", ns)
assert(loadfile("core/aura_glue.lua"))("QUI", ns)
local AuraGlue = ns.AuraGlue
check("core/aura_glue.lua publishes ns.AuraGlue", AuraGlue ~= nil)
check("core/aura_skin.lua publishes ns.Addon.AuraSkin", ns.Addon and ns.Addon.AuraSkin ~= nil)

local profile = { iconSize = 20, maxIcons = 5 }
local groups = { { key = "s1", filter = "HELPFUL", maxFrameCount = 5 } }

----------------------------------------------------------------------------
-- (a) OOC creating pass on a fresh container: baseline registration.
----------------------------------------------------------------------------
inCombat = false
local oocContainer = MakeContainer()
oocContainer:SetUnit("player")
local okOOC = AuraGlue.RunConfigPass(oocContainer, profile, groups, true)
check("OOC RunConfigPass(allowCreate=true) succeeds", okOOC == true)
check("AddAuraGroup was called exactly once (group registered)",
    oocContainer._addAuraGroupCalls == 1, tostring(oocContainer._addAuraGroupCalls))
check("the group key is registered on the container",
    oocContainer._registeredKeys["s1|HELPFUL"] == true)

----------------------------------------------------------------------------
-- (b) Combat pass on the SAME registered container: key reuse, no second
-- AddAuraGroup, mutators reconcile.
----------------------------------------------------------------------------
inCombat = true
oocContainer:SetUnit("party3")
local callsBefore = oocContainer._addAuraGroupCalls
local mutatorsBefore = oocContainer._mutatorCalls
local okCombat = AuraGlue.RunConfigPass(oocContainer, profile, groups, true)
check("combat RunConfigPass on a registered container succeeds", okCombat == true)
check("AddAuraGroup is NOT called again (already-registered key reused)",
    oocContainer._addAuraGroupCalls == callsBefore,
    tostring(oocContainer._addAuraGroupCalls) .. " vs " .. tostring(callsBefore))
check("the live mutators DO run (real reconcile, not a no-op)",
    oocContainer._mutatorCalls > mutatorsBefore)

----------------------------------------------------------------------------
-- (c) THE PTR7 CONTRACT: a FRESH container, IN COMBAT, allowCreate=true —
-- AddAuraGroup runs. This is what lets a mid-combat joiner build its aura
-- pipeline on the spot (prealloc/headroom retired).
----------------------------------------------------------------------------
local combatFresh = MakeContainer()
combatFresh:SetUnit("party4")
local okFresh = AuraGlue.RunConfigPass(combatFresh, profile, groups, true)
check("combat RunConfigPass(allowCreate=true) on a FRESH container succeeds",
    okFresh == true)
check("AddAuraGroup IS called in combat (PTR7 68914 combat-legal creation)",
    combatFresh._addAuraGroupCalls == 1, tostring(combatFresh._addAuraGroupCalls))
check("the group key is registered mid-combat",
    combatFresh._registeredKeys["s1|HELPFUL"] == true)

----------------------------------------------------------------------------
-- (d) The allowCreate=false arm is the SafeCall-GUARDED Configure — with the
-- combat gate gone it registers exactly like the direct arm. No creation
-- gate survives anywhere in core; container CreateFrame policy lives in the
-- consuming ApplyElementPass implementations.
----------------------------------------------------------------------------
local guardedFresh = MakeContainer()
guardedFresh:SetUnit("party5")
local okGuarded = AuraGlue.RunConfigPass(guardedFresh, profile, groups, false)
check("guarded (allowCreate=false) combat pass succeeds", okGuarded == true)
check("guarded pass still registers the group in combat (no gate inside Configure)",
    guardedFresh._addAuraGroupCalls == 1, tostring(guardedFresh._addAuraGroupCalls))
inCombat = false

----------------------------------------------------------------------------
-- (e) Fresh-combat LINEAR-SWIPE creation (stop-gate 2026-07-24): a button
-- born in combat with a linear swipeStyle must get its duration fill
-- IMMEDIATELY — buildButtonArt creates the StatusBar at birth (the
-- pre-restriction initializeFrame window), so styleButton's linear branch
-- WIRES it instead of soft-deferring into a replay that nothing queues
-- (the old permanent-loss path: fill skipped in combat, pass reports
-- success, no regen replay).
----------------------------------------------------------------------------
inCombat = true
local linearProfile = { iconSize = 20, maxIcons = 5, swipeStyle = "horizontal" }
local linearFresh = MakeContainer()
linearFresh:SetUnit("party6")
local okLinear = AuraGlue.RunConfigPass(linearFresh, linearProfile, groups, true)
check("combat linear-swipe creating pass succeeds", okLinear == true)
local born = linearFresh._capturedButton
check("combat-born button carries the birth-created duration fill",
    born ~= nil and born._quiDurationBar ~= nil)
check("SetDurationBar is wired on the combat-born button (no soft deferral)",
    born ~= nil and (born._durationBarCalls or 0) >= 1)
check("the wired bar IS the birth-created fill",
    born ~= nil and born._durationBar == born._quiDurationBar)
inCombat = false

----------------------------------------------------------------------------
-- Mutation-verify the gate removal itself: Configure's AddAuraGroup branch
-- must be a PLAIN else (no combat condition) — pin the source so a
-- reintroduced gate is caught even if the behavioral phases above are
-- rearranged.
----------------------------------------------------------------------------
do
    local skinSrc = assert(io.open("core/aura_skin.lua", "rb")):read("*a")
    check("AuraSkin.Configure registers groups unconditionally (no combat gate)",
        skinSrc:find("elseif not InCombatLockdown() then\n            container:AddAuraGroup", 1, true) == nil)
    check("the unconditional else branch carries the AddAuraGroup call",
        skinSrc:find("container:AddAuraGroup(key, filter, {", 1, true) ~= nil)
end

if fails > 0 then error(fails .. " failure(s) in groupframes_combat_creation_behavior_test") end
print("OK: groupframes_combat_creation_behavior_test (all checks passed)")
