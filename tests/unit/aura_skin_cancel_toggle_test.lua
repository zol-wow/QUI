-- tests/unit/aura_skin_cancel_toggle_test.lua
-- Task 7: right-click cancel toggle must reapply to LIVE groups.
--
-- PTR4 groups are unremovable and a group's initializeFrame closure is
-- handed to the engine ONCE at AddAuraGroup and can never be replaced or
-- re-read by the addon -- so the closure must not bake in the cancelButtons
-- VALUE at creation time. Design (per aura_skin.lua header + task brief):
-- store the CURRENT value on the container (_quiCancelButtons); the
-- initializer reads it at CALL time (not closure-creation time); Configure's
-- restyle loop AND Restyle re-assert it on every registered button every pass.
--
-- Step 0 finding (Blizzard_AuraButton.lua:22-30, AuraButtonSharedMixin --
-- Blizzard_CustomAuraButton.lua does NOT define SetCancelAuraButtons, it lives
-- on the shared AuraButton mixin instead):
--   function AuraButtonSharedMixin:SetCancelAuraButtons(cancelAuraButtons)
--       self.cancelAuraButtonsArray = ParseCancelAuraButtons(cancelAuraButtons);
--       if self.cancelAuraButtonsArray ~= nil then
--           self:RegisterForClicks(unpack(self.cancelAuraButtonsArray));
--       else
--           self:RegisterForClicks();
--       end
--   end
-- ParseCancelAuraButtons(nil) returns nil (line 4-6), so nil DOES clear:
-- RegisterForClicks() with NO arguments empties the button's registered click
-- set. nil is therefore the correct clearing form -- no need for "" instead.
--
-- Behavioral harness: load core/aura_theme.lua + core/aura_skin.lua headless
-- (mirrors tests/unit/aura_skin_layout_center_test.lua) against a plain-table
-- fake container/button pair. The container's AddAuraGroup stub mimics the
-- engine: it captures options.initializeFrame AND invokes it once immediately
-- (first pre-allocated button), so later in the test we can re-invoke that
-- SAME stored closure to simulate the engine handing the group a batch-later
-- button -- the only way to prove the closure re-reads live state instead of
-- a value frozen at MakeInitializer-creation time.
-- Run: lua tests/unit/aura_skin_cancel_toggle_test.lua

local fails = 0
local function check(name, ok)
    if ok then print("  ok  " .. name)
    else fails = fails + 1; print("FAIL  " .. name) end
end

-- Minimal WoW-shaped globals Configure/Restyle/buildButtonArt/styleButton
-- touch. No secure template involved -- Configure only calls METHODS on the
-- container/button objects we hand it, never CreateFrame itself except for
-- the Cooldown swipe child inside buildButtonArt.
_G.InCombatLockdown = function() return false end
_G.AuraContainerSortMethod = { Default = 1 }
_G.AuraContainerSortDirection = { Normal = 1 }
_G.AnchorUtil = { FlowDirection = { Left = -1, Right = 1, Up = 1, Down = -1 }, FlowLayoutAxis = { Horizontal = 0, Vertical = 1 } }

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

-- Fake CustomAuraButton: everything buildButtonArt/styleButton touch is a
-- no-op EXCEPT SetCancelAuraButtons, which records every call so the test
-- can assert both the value AND that it was actually re-invoked.
local function MakeButton()
    local b = Stub()
    b._cancelCallCount = 0
    b._lastCancel = "UNSET"
    function b:SetCancelAuraButtons(v)
        self._cancelCallCount = self._cancelCallCount + 1
        self._lastCancel = v
    end
    function b:SetSize() end
    function b:SetIcon() end
    function b:AddDispelTypeTexture() end
    function b:SetDispelTypeText() end
    function b:SetDurationCooldown() end
    function b:SetDurationText() end
    function b:SetApplicationCount() end
    return b
end

-- Fake CustomAuraContainer. AddAuraGroup mimics the engine: capture the
-- initializeFrame closure (the SAME function reference persists for the
-- group's whole lifetime -- addons cannot replace it) and invoke it once for
-- an initial button, like the engine's pre-allocated first batch.
local function MakeContainer()
    local c = {}
    function c:HasAuraGroup() return false end
    function c:AddAuraGroup(_key, _filter, opts)
        c._lastInitFn = opts.initializeFrame
        c._capturedButton = MakeButton()
        c._lastInitFn(c._capturedButton)
    end
    function c:SetAuraGroupMaxFrameCount() end
    function c:SetAuraGroupSortMethod() end
    function c:SetAuraGroupCandidateFilters() end
    function c:SetAuraGroupLayout() end
    function c:SetFlowLayoutAnchorPoint() end
    function c:SetFlowLayoutGrowthDirection() end
    function c:SetFlowLayoutPadding() end
    function c:SetFlowLayoutAxis() end
    function c:SetFlowLayoutMaximumLineSize() end
    return c
end

local ns = {}
assert(loadfile("core/safecall.lua"))("QUI", ns)
assert(loadfile("core/aura_theme.lua"))("QUI", ns)
assert(loadfile("core/aura_skin.lua"))("QUI", ns)
local AuraSkin = ns.Addon.AuraSkin
check("core/aura_skin.lua publishes ns.Addon.AuraSkin", AuraSkin ~= nil)

local container = MakeContainer()
local profile = { iconSize = 20 }

-- (1) First Configure: cancelButtons="RightButtonUp" -- birth-time initializer
-- must apply it to the engine-created button. (Configure's own trailing
-- restyle loop also re-asserts within this SAME pass since the button is
-- already in container._quiButtons by then -- a harmless second call with the
-- identical value, so this checks the final state, not an exact call count.)
local groupsOn = { { key = "s1", filter = "HELPFUL", cancelButtons = "RightButtonUp" } }
AuraSkin.Configure(container, profile, groupsOn)
local initFn = container._lastInitFn
check("Configure registers the group via AddAuraGroup (initializeFrame captured)",
    type(initFn) == "function")
local button1 = container._capturedButton
check("birth-time initializer applies the configured cancel token",
    button1 ~= nil and button1._lastCancel == "RightButtonUp")

-- (2) Toggle the element's right-click-cancel option OFF and reconfigure.
-- Group key is unchanged ("s1|HELPFUL") -> the ALREADY-REGISTERED path runs
-- (no new AddAuraGroup, no new button) -- this is exactly the toggle bug: the
-- old closure that baked in "RightButtonUp" is never invoked again for
-- button1, so ONLY the Configure restyle loop's explicit re-assert can clear
-- it. Poison first with a sentinel neither Configure call above nor a no-op
-- could coincidentally produce, so this can only pass via a genuine re-assert.
button1._lastCancel = "POISON_BEFORE_TOGGLE_OFF"
local groupsOff = { { key = "s1", filter = "HELPFUL", cancelButtons = nil } }
AuraSkin.Configure(container, profile, groupsOff)
check("Configure's restyle loop re-asserts the CLEARING call on the existing live button",
    button1._lastCancel == nil)

-- (3) A batch-later button born from the ORIGINAL initializeFrame closure
-- (engine reuses the SAME function reference for the group's whole lifetime)
-- must reflect the CURRENT (toggled-off) state, not "RightButtonUp" -- the
-- value that was on groupDesc.cancelButtons when MakeInitializer built this
-- closure. This is the assertion that falsifies "closes over the value"
-- (the pre-fix bug) and confirms the closure reads container._quiCancelButtons
-- at CALL time. button2 starts at the "UNSET" sentinel (never called), so
-- landing on nil (not "UNSET") proves SetCancelAuraButtons(nil) really ran.
local button2 = MakeButton()
initFn(button2)
check("a batch-later button from the STALE closure gets the CURRENT cancel state, not the value frozen at closure-creation",
    button2._lastCancel == nil)

-- (4) Restyle (the combat-legal subset) must also re-assert cancel from
-- whatever Configure last latched onto the container, on every tracked
-- button. Poison both with a sentinel first so this can only pass if Restyle
-- itself performs the re-assert (not by coincidentally inheriting a leftover
-- value from steps 1-3).
button1._lastCancel = "POISON_BEFORE_RESTYLE"
button2._lastCancel = "POISON_BEFORE_RESTYLE"
container._quiCancelButtons = "RightButtonUp"
AuraSkin.Restyle(container, profile)
check("Restyle re-asserts the latched cancel state onto every registered button",
    button1._lastCancel == "RightButtonUp" and button2._lastCancel == "RightButtonUp")

if fails > 0 then error(fails .. " failure(s) in aura_skin_cancel_toggle_test") end
print("OK: aura_skin_cancel_toggle_test (all checks passed)")
