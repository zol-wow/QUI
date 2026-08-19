-- tests/unit/aura_skin_linear_swipe_test.lua
-- Task 8: linear swipe style for filter strips (group buttons).
--
-- Reference: StyleSlot's linear branch (core/aura_slots.lua:93-134) already
-- ports profile.swipeStyle "horizontal"/"vertical" onto tracked slot frames
-- via the engine's SetDurationBar (secret-safe StatusBar fill). This test
-- proves styleButton (core/aura_skin.lua) does the SAME thing for group
-- (strip) buttons: profile.swipeStyle reaches styleButton via
-- container._quiProfile (aura_glue.lua ElementProfile: element.swipeStyle or
-- "radial"), and Configure/Restyle call styleButton on every tracked button.
--
-- Mixin confirmation (tests/framexml/.../Blizzard_CustomAuraButton.lua:183,
-- CustomAuraButtonSharedMixin:SetDurationBar) + Blizzard_CustomAuraButton.xml:5-8
-- (CustomAuraButtonTemplate always inherits CustomAuraButtonInboundMixin =
-- CreateFromMixins(CustomAuraButtonSharedMixin)) + Blizzard_CustomAuraContainer.lua
-- (both AddAuraGroup's CreateCustomFrameProvider and CreateAuraSlotFrame's
-- provider always prepend "CustomAuraButtonTemplate" to templateNames,
-- Blizzard_AuraContainerFrameProviders.lua:34) confirm group-created buttons
-- get SetDurationBar exactly like slot frames -- same forbidden-object legality
-- class relied on for SetDurationCooldown already.
--
-- Harness: mirrors tests/unit/aura_skin_cancel_toggle_test.lua -- fake
-- container/button pair, load core/aura_theme.lua + core/aura_skin.lua
-- headless, drive through AuraSkin.Configure so the SAME code path
-- initializeFrame/Restyle use is exercised (not a direct styleButton call,
-- which isn't exported).
-- Run: lua tests/unit/aura_skin_linear_swipe_test.lua

local fails = 0
local function check(name, ok)
    if ok then print("  ok  " .. name)
    else fails = fails + 1; print("FAIL  " .. name) end
end

_G.InCombatLockdown = function() return false end
_G.AuraContainerSortMethod = { Default = 1 }
_G.AuraContainerSortDirection = { Normal = 1 }
_G.AnchorUtil = { FlowDirection = { Left = -1, Right = 1, Up = 1, Down = -1 }, FlowLayoutAxis = { Horizontal = 0, Vertical = 1 } }
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
    function t:SetDrawEdge() end
    function t:SetDrawBling() end
    function t:SetReverse() end
    function t:SetText() end
    function t:CreateTexture() return Stub() end
    function t:CreateFontString() return Stub() end
    return t
end

-- Fake StatusBar child: records orientation + texture + color so the test
-- can assert styleButton wired it correctly.
local function MakeStatusBar()
    local sb = Stub()
    sb._shown = false
    sb._orientation = nil
    sb._texture = nil
    sb._color = nil
    function sb:SetStatusBarTexture(tex) self._texture = tex end
    function sb:SetOrientation(o) self._orientation = o end
    function sb:SetStatusBarColor(r, g, b, a) self._color = { r, g, b, a } end
    function sb:Show() self._shown = true end
    function sb:Hide() self._shown = false end
    return sb
end

local createdStatusBars = {}
_G.CreateFrame = function(kind, _name, parent)
    if kind == "StatusBar" then
        local sb = MakeStatusBar()
        sb._parent = parent
        createdStatusBars[#createdStatusBars + 1] = sb
        return sb
    end
    return Stub()
end

-- Fake CustomAuraButton: captures SetDurationBar / SetDrawSwipe calls so the
-- test can assert the linear branch actually ran.
local function MakeButton()
    local b = Stub()
    b._cooldown = Stub()
    b._cooldown._drawSwipe = "UNSET"
    b._cooldown._drawEdge = "UNSET"
    b._cooldown._drawBling = "UNSET"
    function b._cooldown:SetDrawSwipe(v) self._drawSwipe = v end
    function b._cooldown:SetDrawEdge(v) self._drawEdge = v end
    function b._cooldown:SetDrawBling(v) self._drawBling = v end
    b._durationBarCalls = 0
    b._lastDurationBar = nil
    b._lastDurationBarOptions = nil
    function b:SetDurationBar(statusBar, options)
        self._durationBarCalls = self._durationBarCalls + 1
        self._lastDurationBar = statusBar
        self._lastDurationBarOptions = options
    end
    function b:SetSize() end
    function b:SetIcon() end
    function b:AddDispelTypeTexture() end
    function b:SetDispelTypeText() end
    function b:SetDurationCooldown() end
    function b:SetDurationText() end
    function b:SetApplicationCount() end
    function b:SetCancelAuraButtons() end
    return b
end

-- buildButtonArt creates the Cooldown child via CreateFrame("Cooldown", ...);
-- intercept that specific call so we can hand back the button's OWN fake
-- cooldown (with the SetDrawSwipe spy) instead of a plain Stub.
local realCreateFrame = _G.CreateFrame
local activeButton
_G.CreateFrame = function(kind, name, parent, template)
    if kind == "Cooldown" and activeButton then
        return activeButton._cooldown
    end
    return realCreateFrame(kind, name, parent, template)
end

local function MakeContainer()
    local c = {}
    function c:HasAuraGroup() return false end
    function c:AddAuraGroup(_key, _filter, opts)
        c._lastInitFn = opts.initializeFrame
        activeButton = MakeButton()
        c._capturedButton = activeButton
        c._lastInitFn(activeButton)
        activeButton = nil
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

-- (1) Configure with swipeStyle = "horizontal": the birth-time initializer
-- (styleButton via MakeInitializer) must disable the radial swipe and wire
-- SetDurationBar with a HORIZONTAL StatusBar + RemainingTime direction.
local container = MakeContainer()
local profileHorizontal = { iconSize = 20, swipeStyle = "horizontal" }
local groups = { { key = "s1", filter = "HELPFUL" } }
AuraSkin.Configure(container, profileHorizontal, groups)
local button1 = container._capturedButton
check("radial swipe disabled when linear style requested",
    button1 ~= nil and button1._cooldown._drawSwipe == false)
check("SetDurationBar was called", button1._durationBarCalls >= 1)
check("SetDurationBar direction defaults to RemainingTime",
    button1._lastDurationBarOptions ~= nil
    and button1._lastDurationBarOptions.direction == Enum.StatusBarTimerDirection.RemainingTime)
check("SetDurationBar interpolation is Immediate",
    button1._lastDurationBarOptions ~= nil
    and button1._lastDurationBarOptions.interpolation == Enum.StatusBarInterpolation.Immediate)
local fill1 = button1._lastDurationBar
check("a StatusBar child was created and passed to SetDurationBar", fill1 ~= nil)
check("the fill StatusBar is oriented HORIZONTAL", fill1 ~= nil and fill1._orientation == "HORIZONTAL")
check("the fill StatusBar is shown", fill1 ~= nil and fill1._shown == true)

-- (2) Reverse Swipe must flip the direction on a later re-style pass
-- (Restyle -- the combat-legal subset -- re-calls styleButton on every
-- tracked button without re-creating anything).
local profileReversed = { iconSize = 20, swipeStyle = "vertical", reverseSwipe = true }
AuraSkin.Restyle(container, profileReversed)
check("Restyle re-wires SetDurationBar on the existing button (no re-creation)",
    button1._durationBarCalls >= 2 and button1._lastDurationBar == fill1)
check("Reverse Swipe flips direction to ElapsedTime",
    button1._lastDurationBarOptions ~= nil
    and button1._lastDurationBarOptions.direction == Enum.StatusBarTimerDirection.ElapsedTime)
check("vertical swipeStyle orients the SAME fill VERTICAL",
    fill1 ~= nil and fill1._orientation == "VERTICAL")
check("no second StatusBar child was created on re-style (fill is cached)",
    #createdStatusBars == 1)

AuraSkin.Restyle(container, { iconSize = 20, swipeStyle = "horizontal", hideSwipe = true })
check("hideSwipe hides a linear duration bar", fill1 ~= nil and fill1._shown == false)
check("hideSwipe disables the Cooldown swipe for a linear strip",
    button1._cooldown._drawSwipe == false)
check("hideSwipe disables the Cooldown edge and bling",
    button1._cooldown._drawEdge == false and button1._cooldown._drawBling == false)

-- (3) Switching BACK to radial must hide the linear fill and restore the
-- Cooldown's radial swipe.
local profileRadial = { iconSize = 20, swipeStyle = "radial" }
AuraSkin.Restyle(container, profileRadial)
check("switching back to radial hides the linear fill", fill1 ~= nil and fill1._shown == false)
check("switching back to radial re-enables the Cooldown radial swipe",
    button1._cooldown._drawSwipe == true)
check("switching back to radial re-enables the Cooldown edge and bling",
    button1._cooldown._drawEdge == true and button1._cooldown._drawBling == true)

if fails > 0 then error(fails .. " failure(s) in aura_skin_linear_swipe_test") end
print("OK: aura_skin_linear_swipe_test (all checks passed)")
