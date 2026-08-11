-- tests/unit/actionbars_extra_button_combat_gate_test.lua
-- Run: lua tests/unit/actionbars_extra_button_combat_gate_test.lua
--
-- Regression guard for the extra-action-button / zone-ability combat handling,
-- the container-anchor topology, and session-long disable behavior.
--
-- ExtraActionBarFrame owns the secure ExtraActionButton1
-- (SecureActionButtonTemplate), so it (and its ancestors, the shared
-- ExtraAbilityContainer included) cannot be reparented or repinned in combat --
-- SetScale/SetParent/ClearAllPoints/SetPoint would be ADDON_ACTION_BLOCKED.
-- ZoneAbilityFrame has NO secure descendant (its spell buttons inherit no
-- secure template), and Blizzard re-adds it to the shared container from
-- UNIT_AURA / SPELLS_CHANGED / ACTIONBAR_SLOT_CHANGED / vehicle events -- all
-- of which fire mid-combat.  The per-path rules:
--
--   1. EXTRA path: combat-gated -- BOTH the settings apply AND the saved
--      frame-anchor apply (a granted button hangs a secure chain under the
--      extra holder, making SetPoint on the holder anchoring-restricted).
--      Ownership is established out of combat by anchoring the shared
--      ExtraAbilityContainer (a stable Blizzard frame Blizzard never
--      reparents on a grant) to the mover, NOT ExtraActionBarFrame.  A
--      mid-combat refresh marks pending; PLAYER_REGEN_ENABLED reconciles.
--   2. ZONE path: no blanket combat gate.  The unprotected ZoneAbilityFrame
--      is reparented onto its own mover, including mid-combat, so an
--      in-combat grant/reparent is reclaimed immediately instead of
--      stranding the button at the Blizzard position until regen.  The
--      reclaim PROBES live protection/anchoring state first through the
--      shared fail-closed helper (Helpers.FrameMutationRestricted): a
--      false answer mutates, a true answer defers, a SECRET answer defers
--      (probed before any truth-test -- truth-testing a secret throws),
--      and a THROWING getter defers (pcall-contained).
--   3. DISABLE path: toggling a surface off resets stock appearance but keeps
--      ownership until /reload.  Live hand-back would mutate protected
--      managed-layout state; next session with both settings off leaves
--      Blizzard untouched.  A stale saved hideArtwork flag is ignored while
--      disabled so the holder spans the restored stock artwork bounds.
--
-- This test proves: (a) in combat the EXTRA path touches NO protected
-- geometry on ExtraActionBarFrame OR the container, applies NO saved frame
-- anchor, and marks pending; (b) in combat the ZONE path DOES reclaim
-- ZoneAbilityFrame and DOES apply its saved frame anchor; (c) the protection
-- probe handles all four query outcomes (false / true / secret / throwing);
-- (d) out of combat the EXTRA path anchors the CONTAINER (never
-- ExtraActionBarFrame:SetParent); (e) disabling keeps ownership monotonic,
-- resets styling, and sizes the holder from stock bounds.

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local CHUNK = "QUI_ActionBars/actionbars/actionbars_extra_buttons.lua"
local UTILS = "core/utils.lua"
local ANCHORING = "modules/layout/anchoring.lua"
local BUILDERS = "QUI_ActionBars/actionbars/actionbars_per_bar_builders.lua"

---------------------------------------------------------------------------
-- Behavioral harness: load the REAL shared helpers (core/utils.lua) and the
-- real chunk with a stubbed environment.
---------------------------------------------------------------------------

-- Secret sentinel + fake probe, installed BEFORE core/utils.lua loads (it
-- caches _G.issecretvalue at file scope).
local SECRET = setmetatable({}, { __tostring = function() return "SECRET" end })
local function fakeIsSecretValue(v) return v == SECRET end
_G.issecretvalue = fakeIsSecretValue
_G.LibStub = function() return nil end

local ns = {}
ns.SafeCall = function(_policy, fn, ...) return pcall(fn, ...) end
ns.SafeCallMethod = function(_policy, obj, name, ...) return pcall(function(...) return obj[name](obj, ...) end, ...) end
ns.SafeCallMethodIfPresent = function(_policy, obj, name, ...) if obj == nil then return nil end local okP, m = pcall(function() return obj[name] end) if not okP then return false end if m == nil then return nil end return pcall(m, obj, ...) end
assert(loadfile(UTILS))("QUI", ns)
assert(ns.Helpers and ns.Helpers.SafeToNumber,
    "core/utils.lua must export Helpers.SafeToNumber")
assert(ns.Helpers.FrameMutationRestricted,
    "core/utils.lua must export the fail-closed Helpers.FrameMutationRestricted")

assert(loadfile("QUI_ActionBars/actionbars/actionbars_env.lua"))("QUI", ns)
local env = ns.ActionBarsEnv

-- Records every protected geometry call made against a Blizzard frame.
local geomCalls = {}
local function record(name)
    geomCalls[#geomCalls + 1] = name
end

-- Frame that scales/reparents/repins (ExtraActionBarFrame, ZoneAbilityFrame).
local function recordingFrame(name, width, height)
    local f = {
        __name = name, button = nil, Style = nil,
        -- Live protection/anchoring answers for the zone in-combat probe.
        protectedNow = false, anchoringRestricted = false,
    }
    function f:GetParent() return nil end
    function f:SetScale(v) self.lastScale = v; record(name .. ":SetScale") end
    function f:SetParent(p) self.lastParent = p; record(name .. ":SetParent") end
    function f:ClearAllPoints() record(name .. ":ClearAllPoints") end
    function f:SetPoint() record(name .. ":SetPoint") end
    function f:GetWidth() return width or 64 end
    function f:GetHeight() return height or 64 end
    function f:SetAlpha(a) self.lastAlpha = a end
    function f:IsMouseEnabled() return false end
    function f:EnableMouse() record(name .. ":EnableMouse") end
    function f:IsProtected() return self.protectedNow end
    function f:IsAnchoringRestricted() return self.anchoringRestricted end
    return f
end

-- ExtraAbilityContainer stub: EditMode system frame with *Base point setters.
-- Base and non-Base variants record under the same normalized name so the
-- assertions do not care which path the code takes.
local function recordingContainer(name)
    local c = {
        __name = name,
        Selection = nil,
        minimumWidth = 250,
        fixedHeight = 120,
        scripts = {},
    }
    function c:GetParent() return nil end
    function c:SetParent(p) self.lastParent = p; record(name .. ":SetParent") end
    function c:ClearAllPoints() record(name .. ":ClearAllPoints") end
    function c:SetPoint(_, _, _, x, y)
        self.lastPointX, self.lastPointY = x, y
        record(name .. ":SetPoint")
    end
    function c:ClearAllPointsBase() record(name .. ":ClearAllPoints") end
    function c:SetPointBase(_, _, _, x, y)
        self.lastPointX, self.lastPointY = x, y
        record(name .. ":SetPoint")
    end
    function c:SetIsLayoutFrame() end
    function c:GetScript(which) return self.scripts[which] end
    function c:SetScript(which, fn) self.scripts[which] = fn end
    function c:AddFrame() end
    function c:Layout() end
    function c:MarkDirty() end
    return c
end

local extraFrame = recordingFrame("ExtraActionBarFrame", 256, 128)
local zoneFrame = recordingFrame("ZoneAbilityFrame")
local container = recordingContainer("ExtraAbilityContainer")
container.frames = { { frame = zoneFrame } }
local originalContainerLayout = container.Layout
local originalContainerMarkDirty = container.MarkDirty

-- Seed Blizzard scripts so the neutralize/restore round-trip is observable.
local blizzOnShow = function() end
local blizzOnHide = function() end
container.scripts.OnShow = blizzOnShow
container.scripts.OnHide = blizzOnHide

local function stubHolder(name)
    return {
        __name = name,
        SetSize = function(self, w, h) self.lastW, self.lastH = w, h end,
        ClearAllPoints = function(self) self.pointCleared = true end,
        SetPoint = function(self, point, rel, relPoint, x, y)
            self.lastPoint, self.lastRel, self.lastRelPoint, self.lastX, self.lastY =
                point, rel, relPoint, x, y
        end,
    }
end

local scheduled = {}
local inCombat = true

-- Chunk-visible _G stub: captures the chunk's global exports and hosts the
-- recording frame-anchor API the chunk reads at call time.
local anchorApplied = {}
local hasAnchorOverride = true
local gStub = {
    QUI_HasFrameAnchor = function() return hasAnchorOverride end,
    QUI_ApplyFrameAnchor = function(key)
        anchorApplied[#anchorApplied + 1] = key
    end,
}
local function resetAnchors()
    for i = #anchorApplied, 1, -1 do anchorApplied[i] = nil end
end
local function anchorSet()
    local seen = {}
    for _, key in ipairs(anchorApplied) do seen[key] = true end
    return seen
end

env._G = gStub
env.UIParent = { __name = "UIParent" }
env.InCombatLockdown = function() return inCombat end
env.issecretvalue = fakeIsSecretValue
env.ExtraActionBarFrame = extraFrame
env.ZoneAbilityFrame = zoneFrame
env.ExtraAbilityContainer = container
-- Capturing hooksecurefunc: records every (object, method) hook body so the
-- lifecycle section below can fire them like Blizzard would.  Capture-only —
-- hooks never fire implicitly, so the sections above drive the chunk's
-- entry points directly, unchanged.
local capturedHooks = {}  -- [object][method] = { fn, ... }
env.hooksecurefunc = function(obj, method, fn)
    local byMethod = capturedHooks[obj]
    if not byMethod then
        byMethod = {}
        capturedHooks[obj] = byMethod
    end
    local list = byMethod[method]
    if not list then
        list = {}
        byMethod[method] = list
    end
    list[#list + 1] = fn
end
env.C_Timer = { After = function(_, fn) scheduled[#scheduled + 1] = fn end }
env.ActionBarsOwned = {}
-- REAL helpers: the zone probe and holder sizing must exercise the actual
-- shared implementation, not a stub.
env.Helpers = ns.Helpers
local extraSettings = { enabled = true, scale = 1.0 }
local zoneSettings = { enabled = true, scale = 1.0 }
env.GetCore = function()
    return {
        db = { profile = { actionBars = { bars = {
            extraActionButton = extraSettings,
            zoneAbility       = zoneSettings,
        } } } },
    }
end

assert(loadfile(CHUNK))("QUI", ns)

local extraHolder = stubHolder("extraHolder")
local zoneHolder = stubHolder("zoneHolder")
env.extraBtnState.extraActionHolder = extraHolder
env.extraBtnState.zoneAbilityHolder = zoneHolder

local ApplyExtraButtonSettings = assert(env.ApplyExtraButtonSettings,
    "chunk must declare ApplyExtraButtonSettings")
local ApplyExtraButtonFrameAnchor = assert(env.ApplyExtraButtonFrameAnchor,
    "chunk must declare ApplyExtraButtonFrameAnchor")
local RefreshExtraButtons = assert(env.RefreshExtraButtons,
    "chunk must declare RefreshExtraButtons")
local QueueExtraButtonReanchor = assert(env.QueueExtraButtonReanchor,
    "chunk must declare QueueExtraButtonReanchor")

local function resetGeom()
    for i = #geomCalls, 1, -1 do geomCalls[i] = nil end
end
local function runScheduled()
    local pending = scheduled
    scheduled = {}
    for _, fn in ipairs(pending) do fn() end
end
local function geomSummary()
    return #geomCalls == 0 and "(none)" or table.concat(geomCalls, ", ")
end
local function seenSet()
    local seen = {}
    for _, c in ipairs(geomCalls) do seen[c] = true end
    return seen
end
local function assertNoProtectedExtraCalls(label)
    local seen = seenSet()
    for _, forbidden in ipairs({
        "ExtraActionBarFrame:SetScale",
        "ExtraActionBarFrame:SetParent",
        "ExtraActionBarFrame:ClearAllPoints",
        "ExtraActionBarFrame:SetPoint",
        "ExtraAbilityContainer:SetParent",
        "ExtraAbilityContainer:ClearAllPoints",
        "ExtraAbilityContainer:SetPoint",
    }) do
        assert(not seen[forbidden],
            label .. " must not call " .. forbidden .. " in combat; got: " .. geomSummary())
    end
end

---------------------------------------------------------------------------
-- FAIL-CLOSED PROBE: Helpers.FrameMutationRestricted must answer all four
-- protection-query outcomes -- false mutable, true restricted, secret
-- restricted (probed before any truth-test), throwing restricted
-- (pcall-contained).  Both getters, plus degenerate frames.
---------------------------------------------------------------------------

local FrameMutationRestricted = ns.Helpers.FrameMutationRestricted

local function probeFrame()
    return {
        IsProtected = function() return false end,
        IsAnchoringRestricted = function() return false end,
    }
end

assert(FrameMutationRestricted(probeFrame()) == false,
    "false/false protection answers must leave the frame mutable")

local f = probeFrame()
f.IsProtected = function() return true end
assert(FrameMutationRestricted(f) == true,
    "a true IsProtected answer must restrict")

f = probeFrame()
f.IsAnchoringRestricted = function() return true end
assert(FrameMutationRestricted(f) == true,
    "a true IsAnchoringRestricted answer must restrict")

f = probeFrame()
f.IsProtected = function() return SECRET end
assert(FrameMutationRestricted(f) == true,
    "a SECRET IsProtected answer must restrict (fail-closed)")

f = probeFrame()
f.IsAnchoringRestricted = function() return SECRET end
assert(FrameMutationRestricted(f) == true,
    "a SECRET IsAnchoringRestricted answer must restrict (fail-closed)")

f = probeFrame()
f.IsProtected = function() error("exec-taint: protection state unreadable") end
assert(FrameMutationRestricted(f) == true,
    "a THROWING IsProtected getter must restrict (fail-closed)")

f = probeFrame()
f.IsAnchoringRestricted = function() error("exec-taint: anchoring state unreadable") end
assert(FrameMutationRestricted(f) == true,
    "a THROWING IsAnchoringRestricted getter must restrict (fail-closed)")

assert(FrameMutationRestricted(nil) == false,
    "nil frame carries nothing to mutate -- callers null-check separately")
assert(FrameMutationRestricted({}) == false,
    "a frame without protection getters (plain addon frame) stays mutable")

---------------------------------------------------------------------------
-- IN COMBAT: the protected EXTRA path defers and marks pending; the
-- unprotected ZONE path reclaims immediately (mid-fight grants).
---------------------------------------------------------------------------

inCombat = true

resetGeom()
env.ActionBarsOwned.pendingExtraButtonRefresh = false
ApplyExtraButtonSettings("extraActionButton")
assert(#geomCalls == 0,
    "ApplyExtraButtonSettings(extra) must make no protected geometry call in combat; got: " .. geomSummary())
assert(env.ActionBarsOwned.pendingExtraButtonRefresh == true,
    "ApplyExtraButtonSettings must mark a pending refresh when gated in combat")

resetGeom()
env.ActionBarsOwned.pendingExtraButtonRefresh = false
ApplyExtraButtonSettings("zoneAbility")
local zoneCombatSeen = seenSet()
for _, expected in ipairs({
    "ZoneAbilityFrame:SetScale",
    "ZoneAbilityFrame:SetParent",
    "ZoneAbilityFrame:ClearAllPoints",
    "ZoneAbilityFrame:SetPoint",
}) do
    assert(zoneCombatSeen[expected],
        "ApplyExtraButtonSettings(zone) must reclaim the unprotected frame IN combat"
            .. " (mid-fight grants); missing " .. expected .. "; got: " .. geomSummary())
end
assertNoProtectedExtraCalls("ApplyExtraButtonSettings(zone)")

-- FRAME-ANCHOR GATE: in combat the extra holder is anchoring-restricted
-- whenever a granted button hangs its secure chain under it -- the saved
-- frame anchor must NOT be applied; the zone holder hosts only the
-- unprotected zone frame, so its anchor applies live.
resetGeom()
resetAnchors()
env.ActionBarsOwned.pendingExtraButtonRefresh = false
ApplyExtraButtonFrameAnchor("extraActionButton")
assert(#anchorApplied == 0,
    "ApplyExtraButtonFrameAnchor(extra) must not apply the saved anchor in combat")
assert(env.ActionBarsOwned.pendingExtraButtonRefresh == true,
    "ApplyExtraButtonFrameAnchor(extra) must mark a pending refresh when gated in combat")

resetAnchors()
ApplyExtraButtonFrameAnchor("zoneAbility")
assert(anchorSet()["zoneAbility"],
    "ApplyExtraButtonFrameAnchor(zone) must apply the saved anchor in combat")

resetGeom()
resetAnchors()
env.ActionBarsOwned.pendingExtraButtonRefresh = false
RefreshExtraButtons()
assertNoProtectedExtraCalls("RefreshExtraButtons")
assert(env.ActionBarsOwned.pendingExtraButtonRefresh == true,
    "RefreshExtraButtons must mark the extra path pending when gated in combat")
assert(seenSet()["ZoneAbilityFrame:SetParent"],
    "RefreshExtraButtons must still apply the unprotected zone path in combat; got: " .. geomSummary())
assert(not anchorSet()["extraActionButton"],
    "RefreshExtraButtons must not apply the extra frame anchor in combat")
assert(anchorSet()["zoneAbility"],
    "RefreshExtraButtons must still apply the zone frame anchor in combat")

resetGeom()
resetAnchors()
env.ActionBarsOwned.pendingExtraButtonRefresh = false
QueueExtraButtonReanchor("extraActionButton")
runScheduled()
assertNoProtectedExtraCalls("QueueExtraButtonReanchor(extra) callback")
assert(env.ActionBarsOwned.pendingExtraButtonRefresh == true,
    "QueueExtraButtonReanchor(extra) must mark a pending refresh when gated in combat")
assert(not anchorSet()["extraActionButton"],
    "QueueExtraButtonReanchor(extra) callback must not apply the frame anchor in combat")

resetGeom()
resetAnchors()
QueueExtraButtonReanchor("zoneAbility")
runScheduled()
assert(seenSet()["ZoneAbilityFrame:SetParent"],
    "QueueExtraButtonReanchor(zone) callback must reclaim in combat; got: " .. geomSummary())
assert(anchorSet()["zoneAbility"],
    "QueueExtraButtonReanchor(zone) callback must apply the zone frame anchor in combat")

---------------------------------------------------------------------------
-- ZONE PROBE (complete path): the in-combat reclaim trusts the client over
-- the static "unprotected" expectation.  All four protection-query outcomes
-- are exercised end-to-end through ApplyExtraButtonSettings: false mutates
-- (proven above), true defers, SECRET defers, THROWING defers.
---------------------------------------------------------------------------

resetGeom()
env.ActionBarsOwned.pendingExtraButtonRefresh = false
zoneFrame.anchoringRestricted = true
ApplyExtraButtonSettings("zoneAbility")
assert(#geomCalls == 0,
    "anchoring-restricted zone frame must not be touched in combat; got: " .. geomSummary())
assert(env.ActionBarsOwned.pendingExtraButtonRefresh == true,
    "anchoring-restricted zone reclaim must defer to regen")
zoneFrame.anchoringRestricted = false

resetGeom()
env.ActionBarsOwned.pendingExtraButtonRefresh = false
zoneFrame.protectedNow = true
ApplyExtraButtonSettings("zoneAbility")
assert(#geomCalls == 0,
    "protected zone frame must not be touched in combat; got: " .. geomSummary())
assert(env.ActionBarsOwned.pendingExtraButtonRefresh == true,
    "protected zone reclaim must defer to regen")
zoneFrame.protectedNow = false

-- The getters' returns are secret-capable (ObjectSecurity aspect); an
-- unreadable answer counts as restricted, and the probe must run BEFORE
-- any truth-test (truth-testing a secret throws).
resetGeom()
env.ActionBarsOwned.pendingExtraButtonRefresh = false
zoneFrame.protectedNow = SECRET
ApplyExtraButtonSettings("zoneAbility")
assert(#geomCalls == 0,
    "secret IsProtected answer must count as restricted; got: " .. geomSummary())
assert(env.ActionBarsOwned.pendingExtraButtonRefresh == true,
    "secret IsProtected answer must defer the reclaim to regen")
zoneFrame.protectedNow = false

resetGeom()
env.ActionBarsOwned.pendingExtraButtonRefresh = false
zoneFrame.anchoringRestricted = SECRET
ApplyExtraButtonSettings("zoneAbility")
assert(#geomCalls == 0,
    "secret IsAnchoringRestricted answer must count as restricted; got: " .. geomSummary())
assert(env.ActionBarsOwned.pendingExtraButtonRefresh == true,
    "secret IsAnchoringRestricted answer must defer the reclaim to regen")
zoneFrame.anchoringRestricted = false

-- The getters can also THROW (exec-taint on the stack).  The probe must
-- contain the error and defer instead of crashing the reclaim.
resetGeom()
env.ActionBarsOwned.pendingExtraButtonRefresh = false
local savedIsProtected = zoneFrame.IsProtected
zoneFrame.IsProtected = function() error("exec-taint: protection state unreadable") end
ApplyExtraButtonSettings("zoneAbility")
assert(#geomCalls == 0,
    "throwing IsProtected getter must count as restricted; got: " .. geomSummary())
assert(env.ActionBarsOwned.pendingExtraButtonRefresh == true,
    "throwing IsProtected getter must defer the reclaim to regen")
zoneFrame.IsProtected = savedIsProtected

resetGeom()
env.ActionBarsOwned.pendingExtraButtonRefresh = false
local savedIsAnchoringRestricted = zoneFrame.IsAnchoringRestricted
zoneFrame.IsAnchoringRestricted = function() error("exec-taint: anchoring state unreadable") end
ApplyExtraButtonSettings("zoneAbility")
assert(#geomCalls == 0,
    "throwing IsAnchoringRestricted getter must count as restricted; got: " .. geomSummary())
assert(env.ActionBarsOwned.pendingExtraButtonRefresh == true,
    "throwing IsAnchoringRestricted getter must defer the reclaim to regen")
zoneFrame.IsAnchoringRestricted = savedIsAnchoringRestricted

---------------------------------------------------------------------------
-- HOLDER PROBE: the reclaim SetParents/SetPoints the zone frame ONTO the
-- holder and then SetSizes the holder itself, so a secure dependent that
-- restricts the HOLDER (zone frame still readable-unrestricted) blocks the
-- same protected mutations.  true, SECRET, and THROWING answers on either
-- holder getter must all defer the reclaim to regen.
---------------------------------------------------------------------------

for _, case in ipairs({
    { label = "true", getter = function() return true end },
    { label = "SECRET", getter = function() return SECRET end },
    { label = "throwing", getter = function() error("exec-taint: holder state unreadable") end },
}) do
    resetGeom()
    env.ActionBarsOwned.pendingExtraButtonRefresh = false
    zoneHolder.IsProtected = case.getter
    ApplyExtraButtonSettings("zoneAbility")
    assert(#geomCalls == 0,
        case.label .. " holder IsProtected answer must defer the zone reclaim; got: " .. geomSummary())
    assert(env.ActionBarsOwned.pendingExtraButtonRefresh == true,
        case.label .. " holder IsProtected answer must defer to regen")
    zoneHolder.IsProtected = nil
end

resetGeom()
env.ActionBarsOwned.pendingExtraButtonRefresh = false
zoneHolder.IsAnchoringRestricted = function() return SECRET end
ApplyExtraButtonSettings("zoneAbility")
assert(#geomCalls == 0,
    "secret holder IsAnchoringRestricted answer must defer the zone reclaim; got: " .. geomSummary())
assert(env.ActionBarsOwned.pendingExtraButtonRefresh == true,
    "secret holder IsAnchoringRestricted answer must defer to regen")
zoneHolder.IsAnchoringRestricted = nil

-- Positive control: with both frame and holder readable-unrestricted the
-- reclaim proceeds again (the holder probe must not fail-closed on a
-- readable false answer).
resetGeom()
ApplyExtraButtonSettings("zoneAbility")
assert(seenSet()["ZoneAbilityFrame:SetParent"],
    "readable-unrestricted holder must let the reclaim proceed; got: " .. geomSummary())

---------------------------------------------------------------------------
-- POSITIVE CONTROL (out of combat): EXTRA anchors the CONTAINER, never
-- ExtraActionBarFrame; ZONE reparents ZoneAbilityFrame; BOTH saved frame
-- anchors apply.  Proves the test can detect a regression instead of
-- passing vacuously.
---------------------------------------------------------------------------

inCombat = false

resetGeom()
resetAnchors()
RefreshExtraButtons()
assert(anchorSet()["extraActionButton"] and anchorSet()["zoneAbility"],
    "out of combat RefreshExtraButtons must apply BOTH saved frame anchors")

resetGeom()
ApplyExtraButtonSettings("extraActionButton")
local extraSeen = seenSet()
for _, expected in ipairs({
    "ExtraActionBarFrame:SetScale",       -- visual scale still on the bar
    "ExtraAbilityContainer:SetParent",    -- position owned via the CONTAINER
    "ExtraAbilityContainer:ClearAllPoints",
    "ExtraAbilityContainer:SetPoint",
}) do
    assert(extraSeen[expected],
        "positive control (extra): out of combat must call " .. expected .. "; got: " .. geomSummary())
end
assert(not extraSeen["ExtraActionBarFrame:SetParent"],
    "extra path must NOT reparent ExtraActionBarFrame (Blizzard keeps it in the container); got: " .. geomSummary())
assert(not extraSeen["ExtraActionBarFrame:ClearAllPoints"] and not extraSeen["ExtraActionBarFrame:SetPoint"],
    "extra path must leave ExtraActionBarFrame anchoring to Blizzard's secure layout; got: " .. geomSummary())
assert(container.Layout == originalContainerLayout and container.MarkDirty == originalContainerMarkDirty,
    "extra path must not replace ExtraAbilityContainer Layout/MarkDirty methods")
assert(container.lastPointX == 0 and container.lastPointY == 4,
    ("native-scale container compensation must be (0, 4); got (%s, %s)")
        :format(tostring(container.lastPointX), tostring(container.lastPointY)))

-- Enabling extra management neutralizes the container's own scripts (they are
-- what re-runs Blizzard managed layout) and remembers the originals.
assert(env.extraBtnState.containerNeutralized == true,
    "enabled extra path must neutralize the container")
assert(container.scripts.OnShow == nil and container.scripts.OnHide == nil,
    "neutralize must clear the container's OnShow/OnHide scripts")

resetGeom()
extraSettings.scale = 1.5
ApplyExtraButtonSettings("extraActionButton")
assert(container.lastPointX == -64 and container.lastPointY == 36,
    ("scaled container compensation must center the visual bar; got (%s, %s)")
        :format(tostring(container.lastPointX), tostring(container.lastPointY)))
extraSettings.scale = 1.0

resetGeom()
ApplyExtraButtonSettings("zoneAbility")
local zoneSeen = seenSet()
for _, expected in ipairs({
    "ZoneAbilityFrame:SetScale",
    "ZoneAbilityFrame:SetParent",
    "ZoneAbilityFrame:ClearAllPoints",
    "ZoneAbilityFrame:SetPoint",
}) do
    assert(zoneSeen[expected],
        "positive control (zone): out of combat must call " .. expected .. "; got: " .. geomSummary())
end

---------------------------------------------------------------------------
-- NO-OVERRIDE FALLBACK: a profile whose mover was never dragged has no raw
-- frameAnchoring override (AceDB strips default-equal entries on save), so
-- QUI_HasFrameAnchor is false and the central anchoring apply skips the
-- key.  The refresh must then snap the holder to the ACTIVE profile's saved
-- bars position (or the creation default) -- without this, a profile
-- switch/import left the holder at the previous profile's position.
---------------------------------------------------------------------------

hasAnchorOverride = false

extraSettings.position = { point = "CENTER", relPoint = "CENTER", x = -120, y = -25 }
zoneSettings.position = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 150, y = -27 }
resetAnchors()
ApplyExtraButtonFrameAnchor("extraActionButton")
ApplyExtraButtonFrameAnchor("zoneAbility")
assert(#anchorApplied == 0,
    "no-override profile must not route through QUI_ApplyFrameAnchor")
assert(extraHolder.pointCleared and extraHolder.lastPoint == "CENTER"
        and extraHolder.lastRel == env.UIParent
        and extraHolder.lastX == -120 and extraHolder.lastY == -25,
    ("no-override refresh must snap the extra holder to the profile's saved position; got (%s, %s, %s)")
        :format(tostring(extraHolder.lastPoint), tostring(extraHolder.lastX), tostring(extraHolder.lastY)))
assert(zoneHolder.pointCleared and zoneHolder.lastPoint == "TOPLEFT"
        and zoneHolder.lastX == 150 and zoneHolder.lastY == -27,
    ("no-override refresh must snap the zone holder to the profile's saved position; got (%s, %s, %s)")
        :format(tostring(zoneHolder.lastPoint), tostring(zoneHolder.lastX), tostring(zoneHolder.lastY)))

-- No saved bars position either: the holder falls back to the creation
-- default instead of keeping a stale point.
extraSettings.position = nil
extraHolder.lastPoint, extraHolder.lastX, extraHolder.lastY = nil, nil, nil
ApplyExtraButtonFrameAnchor("extraActionButton")
assert(extraHolder.lastPoint == "CENTER"
        and extraHolder.lastX == -100 and extraHolder.lastY == -200,
    ("missing saved position must fall back to the creation default; got (%s, %s, %s)")
        :format(tostring(extraHolder.lastPoint), tostring(extraHolder.lastX), tostring(extraHolder.lastY)))

-- In combat the extra fallback defers like the anchor apply (the holder can
-- be anchoring-restricted while a button is up); the zone fallback applies
-- live but defers when the holder probes restricted.
inCombat = true
env.ActionBarsOwned.pendingExtraButtonRefresh = false
extraHolder.lastPoint, extraHolder.lastX, extraHolder.lastY = nil, nil, nil
ApplyExtraButtonFrameAnchor("extraActionButton")
assert(extraHolder.lastPoint == nil,
    "in-combat no-override extra fallback must not SetPoint the holder")
assert(env.ActionBarsOwned.pendingExtraButtonRefresh == true,
    "in-combat no-override extra fallback must defer to regen")

zoneHolder.lastPoint, zoneHolder.lastX = nil, nil
ApplyExtraButtonFrameAnchor("zoneAbility")
assert(zoneHolder.lastPoint == "TOPLEFT" and zoneHolder.lastX == 150,
    "in-combat no-override zone fallback must reposition the unrestricted holder")

env.ActionBarsOwned.pendingExtraButtonRefresh = false
zoneHolder.IsProtected = function() return true end
zoneHolder.lastPoint = nil
ApplyExtraButtonFrameAnchor("zoneAbility")
assert(zoneHolder.lastPoint == nil,
    "in-combat no-override zone fallback must not touch a restricted holder")
assert(env.ActionBarsOwned.pendingExtraButtonRefresh == true,
    "restricted zone holder fallback must defer to regen")
zoneHolder.IsProtected = nil

inCombat = false
hasAnchorOverride = true
extraSettings.position = nil
zoneSettings.position = nil

---------------------------------------------------------------------------
-- HOLDER SIZE vs hideArtwork: while ENABLED the holder shrinks to the
-- visible button footprint; while DISABLED a stale saved hideArtwork flag
-- must be ignored so the holder spans the restored stock artwork bounds.
---------------------------------------------------------------------------

extraFrame.button = {
    GetWidth = function() return 100 end,
    GetHeight = function() return 100 end,
    style = { alpha = nil, SetAlpha = function(self, a) self.alpha = a end },
}
extraSettings.hideArtwork = true
resetGeom()
ApplyExtraButtonSettings("extraActionButton")
assert(extraHolder.lastW == 100 and extraHolder.lastH == 100,
    ("enabled hideArtwork must size the holder to the visual button; got (%s, %s)")
        :format(tostring(extraHolder.lastW), tostring(extraHolder.lastH)))

extraSettings.enabled = false
resetGeom()
ApplyExtraButtonSettings("extraActionButton")
assert(extraHolder.lastW == 256 and extraHolder.lastH == 128,
    ("disabled surface must ignore stale hideArtwork and span stock bounds; got (%s, %s)")
        :format(tostring(extraHolder.lastW), tostring(extraHolder.lastH)))
assert(extraFrame.button.style.alpha == 1,
    "disabled surface must restore stock artwork alpha")
extraSettings.enabled = true
extraSettings.hideArtwork = nil
extraFrame.button = nil

---------------------------------------------------------------------------
-- DISABLE / SESSION OWNERSHIP: toggles reset stock appearance.  Container and
-- zone ownership remain monotonic until /reload, preserving separate movers
-- without mutating Blizzard's managed-frame or ability bookkeeping tables.
---------------------------------------------------------------------------

-- Zone off while extra is ON: zone stays evicted onto its own holder
-- (stock scale, position only), and stale QUI styling from the enabled
-- state (hideArtwork alpha) resets to stock.
zoneFrame.Style = { alpha = nil, SetAlpha = function(self, a) self.alpha = a end }
zoneSettings.hideArtwork = true
ApplyExtraButtonSettings("zoneAbility")   -- enabled + hideArtwork: styles it
assert(zoneFrame.Style.alpha == 0,
    "precondition: enabled hideArtwork hides the zone artwork")
resetGeom()
zoneSettings.enabled = false
ApplyExtraButtonSettings("zoneAbility")
local zoneInvariantSeen = seenSet()
assert(zoneInvariantSeen["ZoneAbilityFrame:SetParent"] and zoneInvariantSeen["ZoneAbilityFrame:SetPoint"],
    "zone-off + extra-on must still evict the zone frame to its own holder; got: " .. geomSummary())
assert(env.extraBtnState.zoneOwned == true,
    "dual-mover invariant keeps zone ownership while extra owns the container")
assert(zoneFrame.ignoreFramePositionManager == true,
    "dual-mover invariant keeps the zone position-manager opt-out")
assert(zoneFrame.Style.alpha == 1,
    "zone-off eviction must reset stale hideArtwork styling to stock")
zoneSettings.enabled = true
zoneSettings.hideArtwork = nil
zoneFrame.Style = nil

-- Extra off IN COMBAT: stock reset/re-anchor is protected -- defer, keep
-- session ownership and make no protected geometry call.
inCombat = true
resetGeom()
env.ActionBarsOwned.pendingExtraButtonRefresh = false
extraSettings.enabled = false
ApplyExtraButtonSettings("extraActionButton")
assertNoProtectedExtraCalls("disabled extra session ownership (combat)")
assert(env.ActionBarsOwned.pendingExtraButtonRefresh == true,
    "in-combat disable of the extra path must defer its stock reset to regen")
assert(env.extraBtnState.containerOwned == true,
    "in-combat disable must keep session ownership")

-- Extra off OUT of combat: reset stock styling, but keep the container pinned,
-- neutralized, and opted out for the rest of the session.
inCombat = false
extraFrame.lastScale = 1.5
extraFrame.lastAlpha = 0.4
extraFrame.button = { style = { alpha = 0, SetAlpha = function(self, a) self.alpha = a end } }
resetGeom()
ApplyExtraButtonSettings("extraActionButton")
assert(seenSet()["ExtraAbilityContainer:SetParent"],
    "disabling extra must keep the container on its holder; got: " .. geomSummary())
assert(env.extraBtnState.containerOwned == true and env.extraBtnState.containerNeutralized == true,
    "disabling extra must retain session ownership and neutralization")
assert(container.scripts.OnShow == nil and container.scripts.OnHide == nil,
    "disabling extra must not restore managed-layout scripts live")
assert(container.ignoreFramePositionManager == true and container.ignoreInLayout == true,
    "disabling extra must retain managed-layout opt-out flags")
assert(container.lastParent == extraHolder,
    "session-owned container must remain on the extra holder")
assert(extraFrame.lastScale == 1,
    "disabling extra must reset ExtraActionBarFrame scale to stock")
assert(extraFrame.lastAlpha == 1,
    "disabling extra must reset ExtraActionBarFrame alpha to stock")
assert(extraFrame.button.style.alpha == 1,
    "disabling extra must reset stale hideArtwork styling on the button artwork")
extraFrame.button = nil

-- BOTH off IN COMBAT: zone remains on its separate holder and resets to stock
-- appearance immediately when live protection probes allow it.  MarkDirty is
-- deferred because the shared container can still own the protected extra bar.
inCombat = true
resetGeom()
env.ActionBarsOwned.pendingExtraButtonRefresh = false
zoneSettings.enabled = false
ApplyExtraButtonSettings("zoneAbility")
local bothOffCombatSeen = seenSet()
assert(bothOffCombatSeen["ZoneAbilityFrame:SetParent"]
        and bothOffCombatSeen["ZoneAbilityFrame:ClearAllPoints"]
        and bothOffCombatSeen["ZoneAbilityFrame:SetPoint"],
    "disabled zone must stay on its separate holder in combat; got: " .. geomSummary())
assertNoProtectedExtraCalls("both disabled zone ownership (combat)")
assert(env.ActionBarsOwned.pendingExtraButtonRefresh == true,
    "in-combat zone MarkDirty must defer to regen")
assert(env.extraBtnState.zoneOwned == true,
    "both disabled must retain zone session ownership")

-- BOTH off OUT of combat: both movers stay owned, with stock appearance.
inCombat = false
resetGeom()
ApplyExtraButtonSettings("extraActionButton")
ApplyExtraButtonSettings("zoneAbility")
local bothOffSeen = seenSet()
assert(bothOffSeen["ExtraAbilityContainer:SetParent"]
        and bothOffSeen["ZoneAbilityFrame:SetParent"]
        and bothOffSeen["ZoneAbilityFrame:SetScale"],
    "both disabled must retain separate session-owned movers; got: " .. geomSummary())
assert(zoneFrame.lastParent == zoneHolder,
    "zone frame must remain on its own holder for the session")
assert(zoneFrame.lastScale == 1,
    "disabled zone must reset scale to stock")
assert(env.extraBtnState.containerOwned == true and env.extraBtnState.zoneOwned == true,
    "both disabled must keep ownership monotonic until reload")
assert(container.ignoreFramePositionManager == true and container.ignoreInLayout == true,
    "both disabled must keep empty container shell out of managed layout")

-- Simulated next session with BOTH off: fresh state leaves Blizzard untouched.
env.extraBtnState.containerOwned = false
env.extraBtnState.containerNeutralized = false
env.extraBtnState.zoneOwned = false
container.ignoreFramePositionManager = nil
container.ignoreInLayout = nil
container.scripts.OnShow = blizzOnShow
container.scripts.OnHide = blizzOnHide
resetGeom()
ApplyExtraButtonSettings("extraActionButton")
ApplyExtraButtonSettings("zoneAbility")
assert(#geomCalls == 0,
    "fresh session with both disabled must leave Blizzard frames untouched; got: " .. geomSummary())
assert(env.extraBtnState.containerOwned == false and env.extraBtnState.zoneOwned == false,
    "fresh session with both disabled must not acquire ownership")

-- Fresh ZONE-only session: extra branch acquires the shared container shell
-- before zone extraction.  Container may remain internally shown because its
-- Blizzard frames entry still counts ZoneAbilityFrame, but it cannot register
-- or reserve the 250x120 bottom-managed layout slot.
zoneSettings.enabled = true
resetGeom()
ApplyExtraButtonSettings("extraActionButton")
ApplyExtraButtonSettings("zoneAbility")
assert(env.extraBtnState.containerOwned == true and env.extraBtnState.containerNeutralized == true,
    "zone-only session must acquire and neutralize the shared container shell")
assert(container.ignoreFramePositionManager == true and container.ignoreInLayout == true,
    "zone-only session must opt the empty container shell out of managed layout")
assert(#container.frames == 1 and container.frames[1].frame == zoneFrame,
    "zone-only ownership must leave Blizzard container membership untouched")
assert(container.lastParent == extraHolder,
    "zone-only container shell must stay on the QUI extra holder, not managed layout")
assert(zoneFrame.lastParent == zoneHolder and env.extraBtnState.zoneOwned == true,
    "zone-only session must keep ZoneAbilityFrame on its separate mover")

zoneSettings.enabled = true
extraSettings.enabled = true

---------------------------------------------------------------------------
-- HOOK LIFECYCLE: the ZoneAbilityFrame:SetParent reclaim hook end-to-end.
-- Blizzard re-adds the zone frame to the shared container mid-combat
-- (UNIT_AURA / SPELLS_CHANGED / grant events).  While a protected dependent
-- restricts the frame, the reclaim DEFERS — the zone frame temporarily
-- rides the extra mover (the deliberate safety exception to the dual-mover
-- invariant) — and the PLAYER_REGEN_ENABLED reconcile (RefreshExtraButtons,
-- see actionbars_events.lua) restores zone ownership.
---------------------------------------------------------------------------

local zoneSetParentHooks = capturedHooks[zoneFrame] and capturedHooks[zoneFrame].SetParent
assert(zoneSetParentHooks and #zoneSetParentHooks >= 1,
    "HookExtraButtonPositioning must hook ZoneAbilityFrame:SetParent")
local zoneSetParentHook = zoneSetParentHooks[1]

-- Restricted mid-combat re-add: the hook defers (no geometry, pending set);
-- the zone frame stays wherever Blizzard parented it until regen.
inCombat = true
zoneFrame.anchoringRestricted = true
env.ActionBarsOwned.pendingExtraButtonRefresh = false
resetGeom()
zoneFrame.lastParent = container
zoneSetParentHook(zoneFrame, container)
runScheduled()
assert(#geomCalls == 0,
    "restricted mid-combat re-add must defer the hook reclaim; got: " .. geomSummary())
assert(env.ActionBarsOwned.pendingExtraButtonRefresh == true,
    "restricted mid-combat re-add must mark pending for the regen reconcile")
assert(zoneFrame.lastParent == container,
    "deferred reclaim leaves the zone frame riding the shared container until regen")

-- Regen reconcile: combat drops, restriction clears; the events chunk clears
-- pending and calls RefreshExtraButtons — zone ownership must be restored.
inCombat = false
zoneFrame.anchoringRestricted = false
env.ActionBarsOwned.pendingExtraButtonRefresh = false
resetGeom()
RefreshExtraButtons()
assert(zoneFrame.lastParent == zoneHolder,
    "regen reconcile must restore the zone frame to its own holder")
assert(seenSet()["ZoneAbilityFrame:SetParent"],
    "regen reconcile must reclaim via SetParent; got: " .. geomSummary())

-- Unrestricted mid-combat re-add: the hook reclaims immediately (mid-fight
-- grant tracking) instead of stranding the button until regen.
inCombat = true
resetGeom()
zoneFrame.lastParent = container
zoneSetParentHook(zoneFrame, container)
runScheduled()
assert(zoneFrame.lastParent == zoneHolder,
    "unrestricted mid-combat re-add must reclaim the zone frame immediately")

-- The hook's re-entry latch: a reclaim-driven SetParent (hookingSetParent
-- latched) must not schedule another reclaim pass.
resetGeom()
local pendingBefore = #scheduled
env.extraBtnState.hookingSetParent = true
zoneSetParentHook(zoneFrame, container)
env.extraBtnState.hookingSetParent = false
assert(#scheduled == pendingBefore,
    "latched SetParent hook must not schedule a reclaim (re-entry guard)")

-- A SetParent onto the zone holder itself is the reclaim landing, not a
-- Blizzard re-add — no reclaim pass either.
zoneSetParentHook(zoneFrame, zoneHolder)
assert(#scheduled == pendingBefore,
    "SetParent onto the zone holder must not schedule a reclaim")

inCombat = false

---------------------------------------------------------------------------
-- SOURCE GUARD: gates, container-anchor topology, and honest comments present.
---------------------------------------------------------------------------

local source = readFile(CHUNK)

-- The PROTECTED extra path must keep its load-bearing combat gate (dropping
-- it on a "both frames are unprotected" premise shipped live taint once).
assert(source:find("COMBAT GATE (load-bearing)", 1, true),
    "extra path must document and keep its combat gate")

-- The extra frame-anchor apply carries its own combat gate: the extra holder
-- is anchoring-restricted whenever a granted button is up.
assert(source:find("COMBAT GATE (extra path)", 1, true),
    "extra frame-anchor apply must document and keep its combat gate")

-- Profiles without a raw frameAnchoring override must still reposition the
-- holder on refresh, and holder creation must share the same fallback.
assert(source:find("NO-OVERRIDE FALLBACK", 1, true),
    "frame-anchor apply must document the no-override fallback")
assert(source:find("function ApplyExtraButtonHolderFallbackPosition", 1, true),
    "no-override fallback must live in a shared helper")
local createStart = assert(source:find("function CreateExtraButtonHolder", 1, true),
    "chunk must declare CreateExtraButtonHolder")
local createBody = source:sub(createStart, createStart + 800)
assert(createBody:find("ApplyExtraButtonHolderFallbackPosition(buttonType, holder)", 1, true),
    "holder creation must position through the shared fallback helper")

-- The zone path's in-combat reclaim rests on the no-secure-descendant fact;
-- keep that justification in the source next to the behavior.
assert(source:find("no secure descendant", 1, true),
    "zone path must document why its in-combat reclaim is safe")

assert(source:find("function ApplyExtraActionContainerAnchor", 1, true),
    "extra path must anchor ExtraAbilityContainer via ApplyExtraActionContainerAnchor")
assert(source:find("container:SetParent(holder)", 1, true),
    "ApplyExtraActionContainerAnchor must parent the container to the holder")
assert(not source:find("container.Layout =", 1, true),
    "extra path must not replace ExtraAbilityContainer.Layout")
assert(not source:find("container.MarkDirty =", 1, true),
    "extra path must not replace ExtraAbilityContainer.MarkDirty")
assert(not source:find('bar:SetPoint("CENTER", holder', 1, true),
    "extra path must not fight Blizzard's secure child layout")

-- Never call the destructive ExtraAbilityContainer:RemoveFrame.
assert(source:find("RemoveFrame", 1, true) and source:find("never call", 1, true),
    "source must document that ExtraAbilityContainer:RemoveFrame is destructive and must not be called")

-- Ownership must be session-long.  Live Restore* paths re-enter Blizzard's
-- protected manager and container layout from insecure code.
assert(source:find("SESSION-LONG OWNERSHIP", 1, true),
    "source must document session-long ownership")
assert(not source:find("function RestoreExtraAbilityContainer", 1, true)
        and not source:find("function RestoreZoneAbilityFrame", 1, true),
    "live disable path must not restore Blizzard ownership")

-- The dual-mover requirement is load-bearing: extra action and zone ability
-- each keep their OWN mover.  One documented exception: a restricted
-- mid-combat reclaim defers, so the zone frame TEMPORARILY rides the extra
-- mover until the regen reconcile (taint-free beats absolute separation in
-- combat).  The invariant doc must name that exception rather than
-- overclaiming "never".
assert(source:find("DUAL-MOVER INVARIANT", 1, true),
    "source must document the dual-mover invariant")
assert(source:find("DELIBERATE SAFETY EXCEPTION", 1, true),
    "source must document the combat safety exception to the dual-mover invariant")
assert(source:find("deliberate safety exception", 1, true),
    "the dual-mover invariant doc must reference the combat safety exception")
assert(source:find("function IsZoneAbilityManaged", 1, true),
    "zone management must be active whenever either surface is enabled")
assert(source:find("function ShouldOwnExtraAbilityContainer", 1, true),
    "either enabled surface must acquire the shared container shell")

-- Protected extra acquisition (settings AND frame anchor) and restricted
-- zone/MarkDirty paths mark pending for the PLAYER_REGEN_ENABLED reconcile.
local gateCount = select(2, source:gsub("ActionBarsOwned%.pendingExtraButtonRefresh = true", ""))
assert(gateCount >= 3,
    "expected >= 3 combat gates marking pendingExtraButtonRefresh, found " .. gateCount)

-- NEVER write into the manager's showingFrames table: an insecure write
-- (raw key removal included) taints it, and the manager's secure pairs()
-- walk then blocks protected ClearAllPoints on the OTHER managed frames
-- (live ADDON_ACTION_BLOCKED).  The transient UpdateManagedFrames clobber
-- is repaired by the container hooks instead.
assert(not source:find("showingFrames[", 1, true)
        and not source:find("showingFrames%s*%["),
    "takeover must never write into the manager's showingFrames table (taint)")
assert(source:find("showingFrames", 1, true),
    "source must document why showingFrames stays untouched")

-- Blizzard alone owns ExtraAbilityContainer.frames membership.  Zone stays in
-- that bookkeeping table while its frame is visually reparented.
assert(not source:find("container%.frames%s*%[")
        and not source:find("table%.remove%s*%(container%.frames"),
    "QUI must never mutate ExtraAbilityContainer.frames")

-- The zone in-combat reclaim must gate on the SHARED fail-closed probe
-- (pcall + issecretvalue before any truth-test) instead of raw getter calls.
assert(source:find("Helpers.FrameMutationRestricted", 1, true),
    "zone reclaim must probe via the shared fail-closed Helpers.FrameMutationRestricted")
assert(not source:find("frame:IsProtected()", 1, true)
        and not source:find("frame:IsAnchoringRestricted()", 1, true),
    "zone reclaim must not raw-call the protection getters (secret/throw unsafe)")

-- A disabled surface ignores stale hideArtwork when sizing the holder.
assert(source:find("settings.enabled == true and settings.hideArtwork", 1, true),
    "holder sizing must honor hideArtwork only while the surface is enabled")

-- The shared helper itself must be fail-closed: pcall both getters and
-- issecretvalue-probe the answers before truth-testing.
local utilsSource = readFile(UTILS)
local helperStart = assert(utilsSource:find("function Helpers.FrameMutationRestricted", 1, true),
    "core/utils.lua must define Helpers.FrameMutationRestricted")
local helperBody = utilsSource:sub(helperStart, helperStart + 900)
assert(helperBody:find("pcall(frame.IsProtected", 1, true)
        and helperBody:find("pcall(frame.IsAnchoringRestricted", 1, true),
    "FrameMutationRestricted must pcall both protection getters")
assert(helperBody:find("issecretvalue(answer)", 1, true),
    "FrameMutationRestricted must issecretvalue-probe before truth-testing")

-- ORDERING: within EACH getter block the issecretvalue probe must run
-- BEFORE the truth-test -- truth-testing a secret answer itself throws, so
-- a reordered block would ship the exact crash the probe exists to prevent.
local protBlockStart = assert(helperBody:find("pcall(frame.IsProtected", 1, true),
    "helper body must contain the IsProtected block")
local anchorBlockStart = assert(helperBody:find("pcall(frame.IsAnchoringRestricted", 1, true),
    "helper body must contain the IsAnchoringRestricted block")
assert(protBlockStart < anchorBlockStart, "unexpected getter block order")
for label, block in pairs({
    IsProtected = helperBody:sub(protBlockStart, anchorBlockStart - 1),
    IsAnchoringRestricted = helperBody:sub(anchorBlockStart),
}) do
    local probeAt = block:find("issecretvalue(answer)", 1, true)
    local truthAt = block:find("if answer then", 1, true)
    assert(probeAt and truthAt and probeAt < truthAt,
        "FrameMutationRestricted " .. label
            .. " block must issecretvalue-probe BEFORE its truth-test")
end

-- The zone reclaim must hand BOTH the zone frame and its holder to the
-- probe (both in-combat call sites: settings apply and SetParent reclaim).
local holderProbeCount = select(2,
    source:gsub("ZoneFrameCombatMutable%(blizzFrame, holder%)", ""))
assert(holderProbeCount >= 2,
    "expected >= 2 ZoneFrameCombatMutable(blizzFrame, holder) call sites, found "
        .. holderProbeCount)

-- The central anchoring path must use the same fail-closed probe for its
-- in-combat defer decision (ApplyFrameAnchor + both hideWithParent sites).
local anchoringSource = readFile(ANCHORING)
local anchoringUses = select(2, anchoringSource:gsub("ns%.Helpers%.FrameMutationRestricted%(", ""))
assert(anchoringUses >= 3,
    "anchoring.lua must gate its in-combat mutations on ns.Helpers.FrameMutationRestricted"
        .. " (combat probe + hide/show sites); found " .. anchoringUses)
assert(not anchoringSource:find("probe:IsProtected()", 1, true)
        and not anchoringSource:find("probe:IsAnchoringRestricted()", 1, true),
    "anchoring.lua combat probe must not raw-call the protection getters")

-- Profile switch/import must refresh the extra/zone surfaces too.
local buildersSource = readFile(BUILDERS)
local registerStart = assert(buildersSource:find('ns.Registry:Register("actionbars"', 1, true),
    "per-bar builders must register the actionbars refresh")
local registerBody = buildersSource:sub(registerStart, registerStart + 900)
assert(registerBody:find("QUI_RefreshExtraButtons", 1, true),
    "registry refresh must reapply extra/zone surfaces on profile switch/import")

-- Fresh defaults must present truly independent movers.
local defaults = readFile("core/defaults.lua")
local frameAnchoringStart = assert(defaults:find("        frameAnchoring = {", 1, true),
    "missing frameAnchoring defaults")
local zoneDefaultStart = assert(defaults:find("            zoneAbility = {", frameAnchoringStart, true),
    "missing zoneAbility frame anchor default")
local zoneDefaultEnd = assert(defaults:find("            },", zoneDefaultStart, true),
    "unterminated zoneAbility frame anchor default")
local zoneDefault = defaults:sub(zoneDefaultStart, zoneDefaultEnd)
assert(zoneDefault:find('parent = "screen"', 1, true)
        and not zoneDefault:find('parent = "extraActionButton"', 1, true),
    "fresh zone mover default must be screen-anchored, not parented to extra mover")

print("OK: actionbars_extra_button_combat_gate_test")
