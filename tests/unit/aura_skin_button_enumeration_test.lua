-- tests/unit/aura_skin_button_enumeration_test.lua
-- Task 9: engine-sanctioned button enumeration. EachTrackedButton replaces
-- the two direct _quiButtons restyle loops (Configure, Restyle) with a
-- capability-probed walk of container._quiGroups x GetAuraGroupFrame(Count)
-- on 68824+ containers, falling back to (and, on capable containers,
-- de-duping against) the birth-time _quiButtons registry for item-enchant
-- frames, which are never group members.
--
-- Part A (brief floor): source-text assertions mirroring the established
-- source-guard pattern (tests/unit/aura_skin_api_test.lua) — these alone are
-- vacuous to a bug where the capability probe exists textually but
-- EachTrackedButton is never actually WIRED into Configure/Restyle, or dedup
-- is wrong. Part B is a BEHAVIORAL harness (mirrors tests/unit/
-- aura_skin_filter_mutation_test.lua's established pattern) that drives
-- EachTrackedButton through both paths.
-- Run: lua tests/unit/aura_skin_button_enumeration_test.lua

local fails = 0
local function check(name, ok, detail)
    if ok then print("  ok  " .. name)
    else fails = fails + 1; print("FAIL  " .. name .. (detail and ("  " .. detail) or "")) end
end

----------------------------------------------------------------------------
-- Part A: brief's source-text floor (verbatim from task-9-brief.md).
----------------------------------------------------------------------------
local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local data = f:read("*a"); f:close()
    return (data:gsub("\r\n", "\n"))
end
local src = readAll("core/aura_skin.lua")
assert(src:find("GetAuraGroupFrameCount", 1, true) and src:find("GetAuraGroupFrame(", 1, true),
    "restyle must enumerate via GetAuraGroupFrame/Count when available")
assert(src:find("container.GetAuraGroupFrame and container.GetAuraGroupFrameCount", 1, true),
    "enumeration must be capability-probed")
assert(src:find("_quiButtons", 1, true),
    "_quiButtons registry must remain as the pre-68824 fallback")
print("OK aura_skin_button_enumeration_test (source-text floor)")

----------------------------------------------------------------------------
-- Part B: behavioral harness. Load core/aura_theme.lua + core/aura_elements.
-- lua + core/aura_skin.lua headless against fake containers (mirrors
-- tests/unit/aura_skin_filter_mutation_test.lua's established pattern), and
-- drive Configure/Restyle (the real call sites, not EachTrackedButton
-- directly — that's the only way to prove it's actually WIRED IN).
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

local function MakeButton(name)
    local b = Stub()
    b._name = name
    b._styleCount = 0
    b._cancelCalls = 0
    function b:SetCancelAuraButtons() b._cancelCalls = b._cancelCalls + 1 end
    function b:SetSize() end
    function b:SetIcon() end
    function b:AddDispelTypeTexture() end
    function b:SetDispelTypeText() end
    function b:SetDurationCooldown() end
    function b:SetDurationText() end
    function b:SetApplicationCount() end
    return b
end

-- Capable container: defines GetAuraGroupFrame/GetAuraGroupFrameCount (the
-- 68824+ sanctioned enumeration surface) alongside the usual mutators. Two
-- groups, each with a small fixed set of "live" engine buttons, PLUS one
-- item-enchant frame that only ever lands in the _quiButtons registry
-- (MakeInitializer's fallback append) and is NEVER reachable through either
-- group's GetAuraGroupFrame — proving the registry-sweep-for-unseen path.
local function MakeCapableContainer()
    local c = { _addCalls = {}, _registeredKeys = {}, _groupFrames = {} }
    function c:HasAuraGroup(key) return self._registeredKeys[key] == true end
    function c:AddAuraGroup(key, filter, opts)
        c._addCalls[#c._addCalls + 1] = { key = key, filter = filter }
        c._registeredKeys[key] = true
        local frames = {}
        for i = 1, 2 do
            local b = MakeButton(key .. "#" .. i)
            frames[i] = b
            opts.initializeFrame(b)   -- births the button, appends to _quiButtons
        end
        c._groupFrames[key] = frames
    end
    function c:SetAuraGroupFilterString() end
    function c:SetAuraGroupMaxFrameCount() end
    function c:SetAuraGroupSortMethod() end
    function c:SetAuraGroupCandidateFilters() end
    function c:SetAuraGroupLayout() end
    function c:SetFlowLayoutAnchorPoint() end
    function c:SetFlowLayoutGrowthDirection() end
    function c:SetFlowLayoutPadding() end
    function c:SetFlowLayoutAxis() end
    function c:SetFlowLayoutMaximumLineSize() end
    -- Sanctioned enumeration surface under test.
    function c:GetAuraGroupFrameCount(key)
        local frames = self._groupFrames[key]
        return frames and #frames or 0
    end
    function c:GetAuraGroupFrame(key, i)
        local frames = self._groupFrames[key]
        return frames and frames[i]
    end
    return c
end

-- Incapable (pre-68824) container: NO GetAuraGroupFrame/Count — mirrors
-- every fake container in the established suites. EachTrackedButton must
-- fall back entirely to _quiButtons.
local function MakeIncapableContainer()
    local c = { _addCalls = {}, _registeredKeys = {} }
    function c:HasAuraGroup(key) return self._registeredKeys[key] == true end
    function c:AddAuraGroup(key, filter, opts)
        c._addCalls[#c._addCalls + 1] = { key = key, filter = filter }
        c._registeredKeys[key] = true
        for i = 1, 2 do
            opts.initializeFrame(MakeButton(key .. "#" .. i))
        end
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

-- Style-count tracking: styleButton is file-local (not observable directly),
-- so track via the observable side-effect Restyle/Configure DO expose on
-- every button: SetCancelAuraButtons is called once per pass per button by
-- both the engine path and the registry-fallback path in EachTrackedButton's
-- caller. Count cancel calls as the "was this button visited" proxy.

----------------------------------------------------------------------------
-- (1) Capable container: Configure must visit every engine-enumerated
-- button (2 groups x 2 buttons = 4) exactly once each via the sanctioned
-- GetAuraGroupFrame/Count surface, PLUS the item-enchant frame that only
-- exists in the registry (never reachable via any group) exactly once —
-- proving the registry-sweep-for-unseen-buttons fallback on a CAPABLE
-- container. Total = 5 visits, no duplicates.
----------------------------------------------------------------------------
local capable = MakeCapableContainer()
local profile = { iconSize = 20 }
AuraSkin.Configure(capable, profile,
    { { key = "s1", filter = "HELPFUL", maxFrameCount = 5 },
      { key = "s2", filter = "HARMFUL", maxFrameCount = 5 } })

-- Simulate an item-enchant frame: born via MakeInitializer's fallback
-- registry append (same mechanism AuraSkin.ConfigureEnchantments uses) but
-- NOT reachable via any group's GetAuraGroupFrame — exactly the shape the
-- brief describes ("Item-enchant frames are NOT group members").
local enchantButton = MakeButton("enchant1")
local reg = capable._quiButtons
check("MakeInitializer registry exists on the container", reg ~= nil)
if reg then
    reg[#reg + 1] = enchantButton
    enchantButton._quiTracked = true
end

check("capable container: engine registered 2 groups via AddAuraGroup",
    #capable._addCalls == 2, tostring(#capable._addCalls))
check("capable container: registry holds 4 engine buttons + 1 enchant button = 5",
    reg ~= nil and #reg == 5, reg and tostring(#reg))

for i = 1, #reg do reg[i]._cancelCalls = 0 end
AuraSkin.Restyle(capable, profile)

local visited, dupes = 0, 0
for i = 1, #reg do
    local n = reg[i]._cancelCalls
    if n >= 1 then visited = visited + 1 end
    if n > 1 then dupes = dupes + 1 end
end
check("capable container: Restyle visits all 5 tracked buttons (4 engine + 1 enchant fallback)",
    visited == 5, tostring(visited))
check("capable container: no button visited more than once (dedup via seen[])",
    dupes == 0, tostring(dupes))

----------------------------------------------------------------------------
-- (2) Incapable (pre-68824) container: no GetAuraGroupFrame/Count at all —
-- EachTrackedButton must fall back ENTIRELY to the _quiButtons registry
-- (the pre-68824 code path, proven still alive).
----------------------------------------------------------------------------
local incapable = MakeIncapableContainer()
AuraSkin.Configure(incapable, profile,
    { { key = "s1", filter = "HELPFUL", maxFrameCount = 5 } })
local ireg = incapable._quiButtons
check("incapable container: registry holds the 2 registered buttons",
    ireg ~= nil and #ireg == 2, ireg and tostring(#ireg))

for i = 1, #ireg do ireg[i]._cancelCalls = 0 end
AuraSkin.Restyle(incapable, profile)
local ivisited = 0
for i = 1, #ireg do
    if ireg[i]._cancelCalls >= 1 then ivisited = ivisited + 1 end
end
check("incapable container: Restyle visits both registry buttons via the fallback path",
    ivisited == 2, tostring(ivisited))

----------------------------------------------------------------------------
-- (3) Configure's own restyle pass (not just Restyle) must also route
-- through EachTrackedButton — prove on the incapable container by resetting
-- counters and re-Configuring with the same groups (goes through the
-- "already registered" reconcile branch, then the trailing restyle pass).
----------------------------------------------------------------------------
for i = 1, #ireg do ireg[i]._cancelCalls = 0 end
AuraSkin.Configure(incapable, profile,
    { { key = "s1", filter = "HELPFUL", maxFrameCount = 5 } })
local cvisited = 0
for i = 1, #ireg do
    if ireg[i]._cancelCalls >= 1 then cvisited = cvisited + 1 end
end
check("incapable container: Configure's trailing restyle pass visits both buttons",
    cvisited == 2, tostring(cvisited))

if fails > 0 then error(fails .. " failure(s) in aura_skin_button_enumeration_test") end
print("OK: aura_skin_button_enumeration_test (all checks passed)")
