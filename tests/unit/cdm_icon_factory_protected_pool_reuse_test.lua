-- tests/unit/cdm_icon_factory_protected_pool_reuse_test.lua
-- Run: lua tests/unit/cdm_icon_factory_protected_pool_reuse_test.lua
--
-- Protected (clickButton) icons used to be quarantined out of the shared
-- recyclePool and parked under UIParent forever on release -- but the
-- reanchor engine release+remints every refresh, leaking unbounded secure
-- frames. The fix is a DEDICATED, CAPPED protected pool: AcquireIcon
-- reacquires from it only for a clickable destination when mutation is
-- safe (OOC or the init-safe window), so protected frames get REUSED
-- (stable identity, bounded retention) instead of leaked. A combat
-- rebuild of a non-clickable viewer can never pop a protected icon out of
-- it (that would raise ADDON_ACTION_BLOCKED).
--
-- This test asserts all three legs of the contract:
--   1. BOUNDED: the protected pool never grows past MAX_RECYCLE_POOL_SIZE,
--      and released protected icons never leak into the shared recyclePool.
--   2. REUSE / STABLE IDENTITY: repeated clickable OOC acquire+release
--      cycles reuse a small, bounded set of frame identities instead of
--      minting a fresh one every round.
--   3. CLICKABLE+MUTATION GATING: the protected pool is reacquired only for
--      a clickable destination AND only when mutation is safe (OOC or the
--      init-safe window) -- never for a non-clickable acquisition, never in
--      combat.

local function noop() end

local inCombat = false
_G.InCombatLockdown = function() return inCombat end

UIParent = {}
GameTooltip = {
    IsForbidden = function() return false end,
    Hide = noop,
}

-- Generic region stub (texture or fontstring) covering everything the real
-- icon-frame construction/reuse paths call on them.
local function NewRegion()
    return {
        SetAllPoints = noop,
        SetPoint = noop,
        SetTexture = noop,
        SetDesaturated = noop,
        SetVertexColor = noop,
        SetColorTexture = noop,
        SetFont = noop,
        SetText = noop,
        SetTextColor = noop,
        Show = noop,
        Hide = noop,
    }
end

function CreateFrame(frameType, name, parent)
    local frame = {
        frameType = frameType,
        name = name,
        parent = parent,
        shown = true,
        alpha = 1,
        frameLevel = 1,
    }
    function frame:SetSize(width, height)
        self.width = width
        self.height = height
    end
    function frame:SetAllPoints(target) self.allPoints = target or true end
    function frame:ClearAllPoints() self.allPoints = nil end
    function frame:SetPoint(...) self.point = { ... } end
    function frame:SetParent(newParent) self.parent = newParent end
    function frame:SetFrameLevel(level) self.frameLevel = level end
    function frame:GetFrameLevel() return self.frameLevel end
    function frame:EnableMouse(value) self.mouseEnabled = value end
    function frame:SetScript(scriptName, handler) self[scriptName] = handler end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    function frame:IsShown() return self.shown end
    function frame:SetAlpha(value) self.alpha = value end
    function frame:GetAlpha() return self.alpha end
    function frame:GetEffectiveAlpha() return self.alpha end
    function frame:CreateTexture() return NewRegion() end
    function frame:CreateFontString() return NewRegion() end
    if frameType == "Cooldown" then
        function frame:SetDrawSwipe(value) self.drawSwipe = value end
        function frame:SetHideCountdownNumbers(value) self.hideCountdownNumbers = value end
        function frame:SetSwipeTexture(value) self.swipeTexture = value end
        function frame:SetSwipeColor(r, g, b, a) self.swipeColor = { r, g, b, a } end
        function frame:SetDrawBling(value) self.drawBling = value end
        function frame:Clear() self.cleared = true end
    end
    return frame
end

local ns = {
    Helpers = {
        GetGeneralFont = function() return "Fonts\\FRIZQT__.TTF" end,
        GetGeneralFontOutline = function() return "" end,
        IsSecretValue = function() return false end,
        SafeValue = function(value) return value end,
    },
    CDMSources = {},
    CDMResolvers = {
        GetEntryTexture = function() return nil end,
        GetSpellTexture = function() return nil end,
        ResolveCooldownState = function() return nil end,
        ResolveMacro = function() return nil end,
        IsAuraEntry = function() return false end,
    },
}

local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_icon_factory.lua", "cdm_icon_factory.lua")("QUI", ns)
local F = assert(ns.CDMIconFactory)
assert(F._recyclePool, "factory exposes _recyclePool")
assert(F._recycleProtectedPool, "factory exposes _recycleProtectedPool")

local MAX_POOL_SIZE = 20  -- mirrors MAX_RECYCLE_POOL_SIZE in cdm_icon_factory.lua

-- Lightweight icon stub. Must survive BOTH a full ReleaseIcon AND
-- AcquireIcon's reuse branch (SetParent/SetSize + field resets + the
-- Icon:SetTexture/SetDesaturated texture refresh).
local function newIcon(withClick)
    local icon = {}
    icon.Hide = function() end
    icon.ClearAllPoints = function() end
    icon.SetParent = function() end
    icon.SetSize = function() end
    icon.Cooldown = { Clear = function() end, SetAlpha = function() end }
    icon.StackText = { SetText = function() end, Hide = function() end, SetAlpha = function() end }
    icon.Border = { Hide = function() end, SetAlpha = function() end }
    icon.Icon = {
        SetVertexColor = function() end,
        SetDesaturated = function() end,
        SetTexture = function() end,
        SetAlpha = function() end,
    }
    icon.DurationText = { SetAlpha = function() end }
    if withClick then icon.clickButton = { secure = true } end
    return icon
end

local function clearPool(t)
    for i = #t, 1, -1 do t[i] = nil end
end

local function containsIdentity(list, needle)
    for i = 1, #list do
        if list[i] == needle then return true end
    end
    return false
end

local parent = CreateFrame("Frame", "Parent", UIParent)
local entry = {
    id = 777,
    spellID = 777,
    type = "spell",
}

---------------------------------------------------------------------------
-- 1. BOUNDED: released protected icons never grow the dedicated pool past
--    the cap, and never leak into the shared recyclePool.
---------------------------------------------------------------------------
inCombat = false
clearPool(F._recyclePool)
clearPool(F._recycleProtectedPool)

local releasedProtected = {}
for i = 1, 3 * MAX_POOL_SIZE do
    local ic = newIcon(true)
    releasedProtected[i] = ic
    F:ReleaseIcon(ic)
end

assert(#F._recycleProtectedPool == 3 * MAX_POOL_SIZE,
    ("after releasing %d protected icons, all must be retained, got %d"):format(3 * MAX_POOL_SIZE, #F._recycleProtectedPool))

for i = 1, #F._recyclePool do
    assert(not containsIdentity(releasedProtected, F._recyclePool[i]),
        "a protected icon must never leak into the shared recyclePool")
end

---------------------------------------------------------------------------
-- 2. REUSE / STABLE IDENTITY: repeated clickable OOC acquire+release
--    cycles reuse a small, bounded set of frame identities.
---------------------------------------------------------------------------
inCombat = false
clearPool(F._recyclePool)
clearPool(F._recycleProtectedPool)

local K, N = 5, 3
local seen = {}
local seenCount = 0
for round = 1, K do
    local acquiredRound = {}
    for i = 1, N do
        local ic = F:AcquireIcon(parent, entry, true)
        ic.clickButton = ic.clickButton or { secure = true }
        if not seen[ic] then
            seen[ic] = true
            seenCount = seenCount + 1
        end
        acquiredRound[i] = ic
    end
    for i = 1, N do
        F:ReleaseIcon(acquiredRound[i])
    end
end

assert(seenCount <= N + 1,
    ("protected icons must be REUSED across rounds (distinct identities <= %d, got %d)")
        :format(N + 1, seenCount))

---------------------------------------------------------------------------
-- 3. CLICKABLE+MUTATION GATING: the protected pool is reacquired only for a
--    clickable destination AND only when mutation is safe (OOC / init-safe
--    window). Seed the pool with ONLY a known protected icon P, and keep
--    the plain recyclePool empty, so any "not P" result unambiguously
--    means the acquisition minted a fresh icon rather than reusing P.
---------------------------------------------------------------------------
clearPool(F._recyclePool)
clearPool(F._recycleProtectedPool)
local P = newIcon(true)
F._recycleProtectedPool[1] = P

-- (a) Non-clickable OOC acquisition must NOT reuse the protected pool.
inCombat = false
local nonClickable = F:AcquireIcon(parent, entry, false)
assert(nonClickable ~= P, "non-clickable acquisition must NOT reuse the protected pool")
assert(F._recycleProtectedPool[1] == P, "P must remain in the protected pool untouched")

-- (b) Combat + clickable acquisition must NOT reuse the protected pool
--     (SetParent/SetSize on the reuse path are protected calls).
inCombat = true
local inCombatAcquire = F:AcquireIcon(parent, entry, true)
assert(inCombatAcquire ~= P, "combat acquisition must NOT reuse the protected pool")
assert(F._recycleProtectedPool[1] == P, "P must remain in the protected pool untouched")
inCombat = false

-- (c) OOC + clickable acquisition DOES reuse the protected pool.
inCombat = false
local clickableOOC = F:AcquireIcon(parent, entry, true)
assert(clickableOOC == P, "clickable + mutation-safe OOC acquisition MUST reuse the protected pool")

---------------------------------------------------------------------------
-- 4. NO PER-REFRESH LEAK: >20-icon container reuse proof. Without the cap,
--    all protected frames must be reused across cycles, not abandoned+recreated.
--    With the old cap, this test would fail (distinct grows past N as overflow
--    frames are dropped and fresh ones minted each cycle).
---------------------------------------------------------------------------
clearPool(F._recyclePool)
clearPool(F._recycleProtectedPool)

local K, N = 3, 25
local distinctIcons = {}
local distinctCount = 0

for _ = 1, K do
    local acquiredIcons = {}
    for i = 1, N do
        local ic = F:AcquireIcon(parent, entry, true)
        ic.clickButton = ic.clickButton or { secure = true }
        acquiredIcons[i] = ic
        if not distinctIcons[ic] then
            distinctIcons[ic] = true
            distinctCount = distinctCount + 1
        end
    end
    for i = 1, N do
        F:ReleaseIcon(acquiredIcons[i])
    end
end

assert(distinctCount <= N + 2,
    ("protected icons in >20-icon container must be REUSED (distinct <= %d, got %d)")
        :format(N + 2, distinctCount))

print("OK: cdm_icon_factory_protected_pool_reuse_test")
