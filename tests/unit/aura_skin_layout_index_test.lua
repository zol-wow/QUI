-- tests/unit/aura_skin_layout_index_test.lua
-- Task 8: explicit group ordering via layoutIndex.
--
-- Part A (brief floor): source-text assertions (established pattern, see
-- tests/unit/aura_skin_api_test.lua). Alone these are vacuous to a bug where
-- layoutIndex is emitted but wired to the wrong value, or g._quiOrder is
-- stamped but never actually consumed by GroupLayout. Part B is a
-- BEHAVIORAL harness proving the discriminating property the brief calls
-- out by name: layoutIndex pins each group's CALLER-array registration
-- order, immune to the fallback path's re-registration (new composite key
-- appends LAST engine-side) reordering the visual layout.
-- Run: lua tests/unit/aura_skin_layout_index_test.lua

local fails = 0
local function check(name, ok, detail)
    if ok then print("  ok  " .. name)
    else fails = fails + 1; print("FAIL  " .. name .. (detail and ("  " .. detail) or "")) end
end

----------------------------------------------------------------------------
-- Part A: brief's source-text floor (verbatim from task-8-brief.md).
----------------------------------------------------------------------------
local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local data = f:read("*a"); f:close()
    return (data:gsub("\r\n", "\n"))
end
local src = readAll("core/aura_skin.lua")
assert(src:find("layoutIndex", 1, true), "GroupLayout must emit layoutIndex")
assert(src:find("g._quiOrder = i", 1, true),
    "Configure must stamp registration order onto each group descriptor")
print("OK aura_skin_layout_index_test (source-text floor)")

----------------------------------------------------------------------------
-- Part B: behavioral harness (mirrors tests/unit/aura_skin_filter_
-- canonicalize_test.lua's established pattern). GroupLayout is file-local,
-- unreachable directly, so this drives it through AuraSkin.Configure and
-- captures every layout table handed to the engine (both at AddAuraGroup
-- time and via SetAuraGroupLayout on the already-registered path).
----------------------------------------------------------------------------
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

-- Incapable container (no SetAuraGroupFilterString): exercises the
-- composite-key fallback re-registration path, the exact scenario the
-- brief's rationale names ("new composite key appends LAST").
local function MakeContainer()
    local c = { _addOrder = {}, _layoutByKey = {}, _registeredKeys = {} }
    function c:HasAuraGroup(key) return self._registeredKeys[key] == true end
    function c:AddAuraGroup(key, filter, opts)
        c._addOrder[#c._addOrder + 1] = key
        c._registeredKeys[key] = true
        c._layoutByKey[key] = opts.layout
        local btn = MakeButton()
        opts.initializeFrame(btn)
    end
    function c:SetAuraGroupMaxFrameCount() end
    function c:SetAuraGroupSortMethod() end
    function c:SetAuraGroupCandidateFilters() end
    function c:SetAuraGroupLayout(key, layout) c._layoutByKey[key] = layout end
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
local profile = { iconSize = 20, iconWidth = 30, iconHeight = 12 }

----------------------------------------------------------------------------
-- (1) Three groups, first Configure: layoutIndex must match CALLER-array
-- position (1, 2, 3), not registration timestamp order (identical here, but
-- this establishes the baseline the next step disturbs).
----------------------------------------------------------------------------
local groups = {
    { key = "s1", filter = "HELPFUL" },
    { key = "s2", filter = "HARMFUL", groupSpacing = 7 },
    { key = "s3", filter = "PLAYER" },
}
AuraSkin.Configure(container, profile, groups)

check("s1 registered first, layoutIndex 1",
    container._layoutByKey["s1|HELPFUL"] and container._layoutByKey["s1|HELPFUL"].layoutIndex == 1,
    container._layoutByKey["s1|HELPFUL"] and tostring(container._layoutByKey["s1|HELPFUL"].layoutIndex))
check("s2 registered second, layoutIndex 2",
    container._layoutByKey["s2|HARMFUL"] and container._layoutByKey["s2|HARMFUL"].layoutIndex == 2,
    container._layoutByKey["s2|HARMFUL"] and tostring(container._layoutByKey["s2|HARMFUL"].layoutIndex))
check("s3 registered third, layoutIndex 3",
    container._layoutByKey["s3|PLAYER"] and container._layoutByKey["s3|PLAYER"].layoutIndex == 3,
    container._layoutByKey["s3|PLAYER"] and tostring(container._layoutByKey["s3|PLAYER"].layoutIndex))
check("rectangular profile dimensions reach group layout",
    container._layoutByKey["s1|HELPFUL"].elementWidth == 30
        and container._layoutByKey["s1|HELPFUL"].elementHeight == 12)
check("per-group spacing reaches group layout",
    container._layoutByKey["s2|HARMFUL"].groupSpacing == 7)

check("Configure stamped g._quiOrder onto every group descriptor in caller order",
    groups[1]._quiOrder == 1 and groups[2]._quiOrder == 2 and groups[3]._quiOrder == 3,
    string.format("%s,%s,%s", tostring(groups[1]._quiOrder), tostring(groups[2]._quiOrder), tostring(groups[3]._quiOrder)))

----------------------------------------------------------------------------
-- (2) THE regression-defining case: s1's filter changes. On the incapable
-- (fallback) container this retires "s1|HELPFUL" and registers a BRAND NEW
-- engine-side key "s1|HARMFUL2" — chronologically the FOURTH AddAuraGroup
-- call (after s1, s2, s3), i.e. LAST in engine creation order. The caller's
-- `groups` array still lists s1 FIRST though. Without layoutIndex the
-- engine would visually append this late-created group last; WITH it,
-- layoutIndex must still read 1, matching the array position — proving
-- explicit ordering survives the fallback path's re-registration.
----------------------------------------------------------------------------
groups[1].filter = "HARMFUL2"
AuraSkin.Configure(container, profile, groups)

check("s1's filter-change registration is chronologically LAST engine-side (4th AddAuraGroup call)",
    #container._addOrder == 4 and container._addOrder[4] == "s1|HARMFUL2",
    string.format("count=%s last=%s", tostring(#container._addOrder), tostring(container._addOrder[4])))
check("...yet its layoutIndex still reads 1 (caller array position), NOT 4 (creation order)",
    container._layoutByKey["s1|HARMFUL2"] and container._layoutByKey["s1|HARMFUL2"].layoutIndex == 1,
    container._layoutByKey["s1|HARMFUL2"] and tostring(container._layoutByKey["s1|HARMFUL2"].layoutIndex))
check("s2 (unchanged, already-registered path) keeps layoutIndex 2",
    container._layoutByKey["s2|HARMFUL"] and container._layoutByKey["s2|HARMFUL"].layoutIndex == 2,
    container._layoutByKey["s2|HARMFUL"] and tostring(container._layoutByKey["s2|HARMFUL"].layoutIndex))
check("s3 (unchanged, already-registered path) keeps layoutIndex 3",
    container._layoutByKey["s3|PLAYER"] and container._layoutByKey["s3|PLAYER"].layoutIndex == 3,
    container._layoutByKey["s3|PLAYER"] and tostring(container._layoutByKey["s3|PLAYER"].layoutIndex))

if fails > 0 then error(fails .. " failure(s) in aura_skin_layout_index_test") end
print("OK: aura_skin_layout_index_test (all checks passed)")
