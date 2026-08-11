-- tests/unit/aura_skin_filter_canonicalize_test.lua
-- Wave 4 Task 4 (4a): end-to-end proof that AuraSkin.Configure's composite
-- registry key (gkey.."|"..filter) is derived from the CANONICAL filter
-- string, not the raw one — the actual payoff of canonicalization: settings
-- that resolve to the SAME semantic filter through a differently-ordered/
-- cased/whitespace-padded string must reuse the EXISTING engine group
-- instead of registering a fresh, orphaned one (PTR4 groups are
-- addon-unremovable — see core/aura_skin.lua header).
--
-- Behavioral harness: load core/aura_theme.lua + core/aura_elements.lua +
-- core/aura_skin.lua headless against a plain-table fake container (mirrors
-- tests/unit/aura_skin_cancel_toggle_test.lua's established pattern).
-- Run: lua tests/unit/aura_skin_filter_canonicalize_test.lua

local fails = 0
local function check(name, ok, detail)
    if ok then print("  ok  " .. name)
    else fails = fails + 1; print("FAIL  " .. name .. (detail and ("  " .. detail) or "")) end
end

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

local function MakeButton()
    local b = Stub()
    function b:SetCancelAuraButtons() end
    function b:SetSize() end
    function b:SetIcon() end
    function b:AddDispelTypeTexture() end
    function b:SetDispelTypeText() end
    function b:SetDurationCooldown() end
    function b:SetDurationText() end
    function b:SetApplicationCount() end
    return b
end

-- Fake CustomAuraContainer. AddAuraGroup mimics the engine exactly like the
-- cancel-toggle test's harness, PLUS records every (key, filter) pair
-- registered so the test can assert AddAuraGroup fired exactly once across
-- two Configure calls with textually-different-but-canonically-equal
-- filters.
local function MakeContainer()
    local c = { _addCalls = {}, _registeredKeys = {} }
    function c:HasAuraGroup(key) return self._registeredKeys[key] == true end
    function c:AddAuraGroup(key, filter, opts)
        c._addCalls[#c._addCalls + 1] = { key = key, filter = filter }
        c._registeredKeys[key] = true
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

-- Load order mirrors QUI.toc: aura_skin.lua BEFORE aura_elements.lua (the
-- reason AuraSkin.Configure resolves ns.AuraElements lazily — see
-- core/aura_skin.lua's ResolveAuraElements comment). Loading in this exact
-- order in the test exercises that lazy-resolve path for real, not just the
-- happy case where the model happens to already be present.
local ns = {}
assert(loadfile("core/safecall.lua"))("QUI", ns)
assert(loadfile("core/aura_theme.lua"))("QUI", ns)
assert(loadfile("core/aura_skin.lua"))("QUI", ns)
assert(loadfile("core/aura_elements.lua"))("QUI", ns)
local AuraSkin = ns.Addon.AuraSkin
check("core/aura_skin.lua publishes ns.Addon.AuraSkin", AuraSkin ~= nil)
check("core/aura_elements.lua publishes ns.AuraElements.CanonicalizeFilterString",
    ns.AuraElements and type(ns.AuraElements.CanonicalizeFilterString) == "function")

local container = MakeContainer()
local profile = { iconSize = 20 }

----------------------------------------------------------------------------
-- (1) First Configure: register a group whose filter is UN-canonical
-- (deliberately shuffled + differently cased-but-otherwise-valid order is
-- NOT what this element's structured model would ever emit — this
-- simulates "any future producer" per the defensive wiring comment in
-- AuraSkin.Configure). The REGISTERED filter string must be the CANONICAL
-- form, not the raw one handed in.
----------------------------------------------------------------------------
local raw1 = "RAID|HELPFUL|PLAYER"
local canonical = "HELPFUL|PLAYER|RAID"
AuraSkin.Configure(container, profile, { { key = "s1", filter = raw1, maxFrameCount = 5 } })
check("AddAuraGroup called once for the first Configure", #container._addCalls == 1)
check("registered filter string is CANONICAL, not the raw input",
    container._addCalls[1].filter == canonical, container._addCalls[1].filter)
check("registry key embeds the canonical filter",
    container._addCalls[1].key == "s1|" .. canonical, container._addCalls[1].key)

----------------------------------------------------------------------------
-- (2) Second Configure: a DIFFERENT raw ordering of the SAME token set
-- (what an equivalent settings state re-derived a different way would look
-- like). This is the actual payoff: it must NOT register a second group —
-- PTR4 groups are addon-unremovable, so a naive raw-string key would leak
-- an orphaned group here every time the raw ordering drifts.
----------------------------------------------------------------------------
local raw2 = "PLAYER|RAID|HELPFUL"
AuraSkin.Configure(container, profile, { { key = "s1", filter = raw2, maxFrameCount = 5 } })
check("second Configure with a differently-ORDERED equal filter does NOT call AddAuraGroup again",
    #container._addCalls == 1, tostring(#container._addCalls))

----------------------------------------------------------------------------
-- (3) A GENUINELY different filter (different token set, not just
-- reordered) still gets its own group — canonicalization must not collapse
-- semantically distinct filters.
----------------------------------------------------------------------------
AuraSkin.Configure(container, profile, { { key = "s1", filter = "HELPFUL|CANCELABLE", maxFrameCount = 5 } })
check("a genuinely different filter still registers its own group",
    #container._addCalls == 2, tostring(#container._addCalls))
check("the new group's filter is canonical too",
    container._addCalls[2].filter == "HELPFUL|CANCELABLE", container._addCalls[2].filter)

if fails > 0 then error(fails .. " failure(s) in aura_skin_filter_canonicalize_test") end
print("OK: aura_skin_filter_canonicalize_test (all checks passed)")
