-- tests/unit/aura_skin_filter_mutation_test.lua
-- Task 7: stable group keys via SetAuraGroupFilterString (capability-probed),
-- composite-key scheme kept verbatim as the pre-68824 fallback.
--
-- Part A (brief floor): source-text assertions mirroring the established
-- source-guard pattern (tests/unit/aura_skin_api_test.lua) — these alone are
-- vacuous to a bug where the capability probe exists textually but the
-- branch logic is wrong (e.g. always calling SetAuraGroupFilterString even
-- when unchanged, or never actually keeping the key bare). Part B below is a
-- BEHAVIORAL harness (mirrors tests/unit/aura_skin_filter_canonicalize_test.
-- lua's established pattern) that proves the discriminating properties the
-- textual checks can't: (1) the registry KEY stays the bare group key across
-- a filter change on a capable container — the actual "stable key" payoff —
-- (2) SetAuraGroupFilterString is called ONLY when the filter actually
-- changed (registered[key] ~= filter gate), not on every Configure pass, and
-- (3) a container WITHOUT the capability still uses the composite key and
-- registers a fresh group per distinct filter, unchanged from pre-68824
-- behavior.
-- Run: lua tests/unit/aura_skin_filter_mutation_test.lua

local fails = 0
local function check(name, ok, detail)
    if ok then print("  ok  " .. name)
    else fails = fails + 1; print("FAIL  " .. name .. (detail and ("  " .. detail) or "")) end
end

----------------------------------------------------------------------------
-- Part A: brief's source-text floor (verbatim from task-7-brief.md).
----------------------------------------------------------------------------
local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local data = f:read("*a"); f:close()
    return (data:gsub("\r\n", "\n"))
end
local src = readAll("core/aura_skin.lua")
assert(src:find("SetAuraGroupFilterString", 1, true),
    "Configure must adopt SetAuraGroupFilterString on capable containers")
assert(src:find("container.SetAuraGroupFilterString", 1, true),
    "adoption must be capability-probed (container.SetAuraGroupFilterString)")
-- Fallback must survive for pre-68824 clients:
assert(src:find('gkey .. "|" .. filter', 1, true),
    "composite-key fallback for filter-immutable containers must remain")
-- Registry must record the applied filter so change detection works:
assert(src:find("registered[key] = filter", 1, true),
    "registry must store the applied filter string per key")
print("OK aura_skin_filter_mutation_test (source-text floor)")

----------------------------------------------------------------------------
-- Part B: behavioral harness. Load core/aura_theme.lua + core/aura_elements.
-- lua + core/aura_skin.lua headless against fake containers (mirrors
-- tests/unit/aura_skin_filter_canonicalize_test.lua's established pattern).
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

-- Capable container: defines SetAuraGroupFilterString, so canMutateFilter
-- must be true and the registry key must stay the BARE group key.
local function MakeCapableContainer()
    local c = { _addCalls = {}, _filterCalls = {}, _registeredKeys = {} }
    function c:HasAuraGroup(key) return self._registeredKeys[key] == true end
    function c:AddAuraGroup(key, filter, opts)
        c._addCalls[#c._addCalls + 1] = { key = key, filter = filter }
        c._registeredKeys[key] = true
        c._lastInitFn = opts.initializeFrame
        c._capturedButton = MakeButton()
        c._lastInitFn(c._capturedButton)
    end
    function c:SetAuraGroupFilterString(key, filter)
        c._filterCalls[#c._filterCalls + 1] = { key = key, filter = filter }
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

-- Incapable container: NO SetAuraGroupFilterString, mirrors every other
-- fake container in this suite — proves the fallback is untouched.
local function MakeIncapableContainer()
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

local ns = {}
assert(loadfile("core/safecall.lua"))("QUI", ns)
assert(loadfile("core/aura_theme.lua"))("QUI", ns)
assert(loadfile("core/aura_skin.lua"))("QUI", ns)
assert(loadfile("core/aura_elements.lua"))("QUI", ns)
local AuraSkin = ns.Addon.AuraSkin
check("core/aura_skin.lua publishes ns.Addon.AuraSkin", AuraSkin ~= nil)

----------------------------------------------------------------------------
-- (1) Capable container: first Configure registers via AddAuraGroup with
-- the BARE key (no "|" — the stable-key payoff), not the composite form.
----------------------------------------------------------------------------
local capable = MakeCapableContainer()
local profile = { iconSize = 20 }
AuraSkin.Configure(capable, profile, { { key = "s1", filter = "HELPFUL", maxFrameCount = 5 } })
check("capable container: AddAuraGroup called once", #capable._addCalls == 1,
    tostring(#capable._addCalls))
check("capable container: registry key is the BARE group key, not composite",
    capable._addCalls[1].key == "s1", tostring(capable._addCalls[1].key))
check("capable container: no SetAuraGroupFilterString call on first (new) registration",
    #capable._filterCalls == 0, tostring(#capable._filterCalls))

----------------------------------------------------------------------------
-- (2) Same key, CHANGED filter: must NOT re-register (AddAuraGroup stays at
-- 1 — the actual "stable key" property under test) and must mutate via
-- SetAuraGroupFilterString(key, newFilter) exactly once, using the SAME
-- bare key as before.
----------------------------------------------------------------------------
AuraSkin.Configure(capable, profile, { { key = "s1", filter = "HARMFUL", maxFrameCount = 5 } })
check("capable container: filter change does NOT create a second group",
    #capable._addCalls == 1, tostring(#capable._addCalls))
check("capable container: SetAuraGroupFilterString called once for the changed filter",
    #capable._filterCalls == 1, tostring(#capable._filterCalls))
check("capable container: mutation targets the SAME bare key",
    capable._filterCalls[1] and capable._filterCalls[1].key == "s1",
    capable._filterCalls[1] and tostring(capable._filterCalls[1].key))
check("capable container: mutation carries the new filter",
    capable._filterCalls[1] and capable._filterCalls[1].filter == "HARMFUL",
    capable._filterCalls[1] and tostring(capable._filterCalls[1].filter))

----------------------------------------------------------------------------
-- (3) Re-Configure with the SAME (unchanged) filter: SetAuraGroupFilterString
-- must NOT fire again — proves the change-detection gate (registered[key]
-- ~= filter), not an unconditional re-mutate on every pass. Vacuous without
-- this: a naive "always call SetAuraGroupFilterString" implementation would
-- also pass checks (1)-(2)-(4) above.
----------------------------------------------------------------------------
AuraSkin.Configure(capable, profile, { { key = "s1", filter = "HARMFUL", maxFrameCount = 5 } })
check("capable container: unchanged filter does NOT re-invoke SetAuraGroupFilterString",
    #capable._filterCalls == 1, tostring(#capable._filterCalls))

----------------------------------------------------------------------------
-- (4) Incapable container (no SetAuraGroupFilterString): unchanged from
-- pre-68824 behavior — a filter change on the same key registers a FRESH
-- composite-key group, old key silently retired (never re-registers).
----------------------------------------------------------------------------
local incapable = MakeIncapableContainer()
AuraSkin.Configure(incapable, profile, { { key = "s1", filter = "HELPFUL", maxFrameCount = 5 } })
check("incapable container: first registration uses composite key",
    incapable._addCalls[1].key == "s1|HELPFUL", tostring(incapable._addCalls[1].key))
AuraSkin.Configure(incapable, profile, { { key = "s1", filter = "HARMFUL", maxFrameCount = 5 } })
check("incapable container: filter change registers a SECOND (composite-key) group",
    #incapable._addCalls == 2, tostring(#incapable._addCalls))
check("incapable container: second group's key is the new composite key",
    incapable._addCalls[2] and incapable._addCalls[2].key == "s1|HARMFUL",
    incapable._addCalls[2] and tostring(incapable._addCalls[2].key))

if fails > 0 then error(fails .. " failure(s) in aura_skin_filter_mutation_test") end
print("OK: aura_skin_filter_mutation_test (all checks passed)")
